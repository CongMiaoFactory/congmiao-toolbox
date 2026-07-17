<script lang="ts">
  import { appState } from '../state.svelte';
  import { commandTools } from '../toolRegistry';
  import { runTool } from '../tools';
  import { tick, onMount } from 'svelte';

  let commandInput = $state<HTMLInputElement | null>(null);

  const fuzzyScore = (query: string, target: string) => {
    if (!query) return 1;
    let score = 0;
    let targetIndex = 0;
    let streak = 0;

    for (const char of query) {
      const foundAt = target.indexOf(char, targetIndex);
      if (foundAt === -1) return -1;
      streak = foundAt === targetIndex ? streak + 1 : 1;
      score += 3 + streak;
      targetIndex = foundAt + 1;
    }
    return score;
  };

  let filteredCommands = $derived.by(() => {
    const query = appState.commandQuery.trim().toLowerCase();
    const results = commandTools
      .map((command) => {
        const haystack = [command.title, command.description, command.shortcut ?? '', ...command.keywords].join(' ').toLowerCase();
        return { command, score: fuzzyScore(query, haystack) };
      })
      .filter((entry) => entry.score >= 0)
      .sort((a, b) => b.score - a.score);
    return results.map((entry) => entry.command);
  });

  $effect(() => {
    if (appState.commandOpen && commandInput) {
      tick().then(() => {
        commandInput?.focus();
        commandInput?.select();
      });
    }
  });

  $effect(() => {
    if (filteredCommands.length === 0) {
      appState.commandIndex = 0;
    } else if (appState.commandIndex > filteredCommands.length - 1) {
      appState.commandIndex = filteredCommands.length - 1;
    }
  });

  async function activateCommand(command: typeof commandTools[0] | undefined) {
    if (!command) return;
    appState.commandOpen = false;
    appState.commandQuery = '';
    await runTool(command.id);
  }

  function handleKeydown(e: KeyboardEvent) {
    if (e.key === 'Escape') {
      e.preventDefault();
      appState.commandOpen = false;
      return;
    }
    if (e.key === 'ArrowDown') {
      e.preventDefault();
      if (filteredCommands.length > 0) {
        appState.commandIndex = (appState.commandIndex + 1) % filteredCommands.length;
      }
      return;
    }
    if (e.key === 'ArrowUp') {
      e.preventDefault();
      if (filteredCommands.length > 0) {
        appState.commandIndex = (appState.commandIndex - 1 + filteredCommands.length) % filteredCommands.length;
      }
      return;
    }
    if (e.key === 'Enter') {
      e.preventDefault();
      activateCommand(filteredCommands[appState.commandIndex]);
    }
  }
</script>

{#if appState.commandOpen}
  <!-- svelte-ignore a11y_click_events_have_key_events -->
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <div class="overlay" onclick={() => appState.commandOpen = false}>
    <div class="palette" onclick={(e) => e.stopPropagation()}>
      <div class="search-box">
        <span class="material-symbols-rounded">search</span>
        <input
          bind:this={commandInput}
          bind:value={appState.commandQuery}
          onkeydown={handleKeydown}
          placeholder="搜索命令或输入工具名称..."
          autocomplete="off"
          spellcheck="false"
        />
        <div class="shortcut">ESC 取消</div>
      </div>
      
      <div class="results">
        {#each filteredCommands as cmd, i}
          <button
            class="result-item {i === appState.commandIndex ? 'active' : ''}"
            onmousemove={() => appState.commandIndex = i}
            onclick={() => activateCommand(cmd)}
          >
            <div class="icon-wrap {cmd.accent}">
              <span class="material-symbols-rounded">{cmd.icon}</span>
            </div>
            <div class="result-text">
              <span class="title">{cmd.title}</span>
              <span class="subtitle">{cmd.description}</span>
            </div>
            {#if cmd.shortcut}<div class="cmd-shortcut">{cmd.shortcut}</div>{/if}
          </button>
        {/each}
        {#if filteredCommands.length === 0}
          <div class="empty-state">没有找到相关命令</div>
        {/if}
      </div>
    </div>
  </div>
{/if}

<style>
  .overlay {
    position: fixed;
    inset: 0;
    z-index: 100;
    display: flex;
    justify-content: center;
    align-items: flex-start;
    padding-top: 12vh;
    background-color: rgba(0, 0, 0, 0.4);
    backdrop-filter: blur(8px);
    animation: fadeIn 0.2s cubic-bezier(0.2, 0.8, 0.2, 1);
  }

  .palette {
    width: 640px;
    max-width: 90vw;
    background-color: var(--bg-panel0);
    border: 1px solid var(--border-subtle);
    border-radius: var(--radius-lg);
    box-shadow: var(--shadow-lg), 0 0 0 1px rgba(255, 255, 255, 0.05) inset;
    overflow: hidden;
    animation: slideDown 0.2s cubic-bezier(0.2, 0.8, 0.2, 1);
  }

  .search-box {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 16px 20px;
    border-bottom: 1px solid var(--border-focus);
    background-color: var(--bg-panel1);
  }

  .search-box .material-symbols-rounded {
    color: var(--text-secondary);
    font-size: 24px;
  }

  input {
    flex: 1;
    background: transparent;
    border: none;
    color: var(--text-primary);
    font-size: 18px;
    outline: none;
  }

  input::placeholder {
    color: var(--text-caption);
  }

  .shortcut {
    font-size: 11px;
    font-weight: 600;
    color: var(--text-caption);
    background-color: var(--bg-app);
    padding: 4px 8px;
    border-radius: 6px;
    border: 1px solid var(--border-subtle);
  }

  .results {
    max-height: 400px;
    overflow-y: auto;
    padding: 8px;
  }

  .result-item {
    display: flex;
    align-items: center;
    gap: 16px;
    width: 100%;
    padding: 12px 16px;
    border-radius: var(--radius-md);
    text-align: left;
    transition: background-color 0.1s;
  }

  .result-item.active {
    background-color: var(--bg-panel-hover);
  }

  .icon-wrap {
    display: grid;
    place-items: center;
    width: 40px;
    height: 40px;
    border-radius: 12px;
    background-color: var(--bg-app);
    border: 1px solid var(--border-subtle);
  }
  
  .icon-wrap.teal { color: var(--accent-teal); }
  .icon-wrap.blue { color: var(--accent-blue); }

  .result-text {
    display: flex;
    flex-direction: column;
    flex: 1;
    gap: 2px;
  }

  .title {
    font-size: 15px;
    font-weight: 600;
    color: var(--text-primary);
  }

  .subtitle {
    font-size: 13px;
    color: var(--text-caption);
  }

  .cmd-shortcut {
    font-size: 12px;
    color: var(--text-caption);
    font-family: monospace;
    background-color: var(--bg-app);
    padding: 4px 8px;
    border-radius: 6px;
  }

  .empty-state {
    padding: 32px;
    text-align: center;
    color: var(--text-caption);
    font-size: 14px;
  }

  @keyframes fadeIn {
    from { opacity: 0; }
    to { opacity: 1; }
  }

  @keyframes slideDown {
    from { transform: scale(0.98) translateY(-10px); opacity: 0; }
    to { transform: scale(1) translateY(0); opacity: 1; }
  }
</style>
