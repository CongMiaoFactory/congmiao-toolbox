<script lang="ts">
  import { tick } from 'svelte';
  import { openUrl } from '@tauri-apps/plugin-opener';
  import { appState } from '../state.svelte';
  import { commandTools } from '../toolRegistry';
  import { buildLauncherResults, type LauncherResult } from '../launcher';
  import { copyText, runTool } from '../tools';
  import { errorMessage, toast } from '../toast.svelte';

  let commandInput = $state<HTMLInputElement | null>(null);
  let busy = $state(false);

  const results = $derived(buildLauncherResults(
    appState.commandQuery,
    commandTools,
    appState.workspaceTemplates,
    appState.favorites,
    appState.recentTools,
  ));

  $effect(() => {
    if (appState.commandOpen && commandInput) {
      void tick().then(() => {
        commandInput?.focus();
        if (appState.commandQuery) commandInput?.setSelectionRange(appState.commandQuery.length, appState.commandQuery.length);
        else commandInput?.select();
      });
    }
  });

  $effect(() => {
    if (results.length === 0) appState.commandIndex = 0;
    else if (appState.commandIndex > results.length - 1) appState.commandIndex = results.length - 1;
  });

  function closePalette() {
    appState.commandOpen = false;
    appState.commandQuery = '';
    appState.commandIndex = 0;
  }

  async function activate(result: LauncherResult | undefined) {
    if (!result || busy) return;
    busy = true;
    try {
      if (result.kind === 'tool' && result.toolId) {
        closePalette();
        await runTool(result.toolId);
      } else if (result.kind === 'workspace' && result.templateId) {
        appState.applyWorkspaceTemplate(result.templateId);
        closePalette();
        toast.success(`已切换到工作区“${result.title}”`);
      } else if (result.kind === 'todo' && result.value) {
        appState.addTodo(result.value);
        closePalette();
        toast.success('待办已添加');
      } else if (result.kind === 'timer' && result.seconds) {
        const milliseconds = result.seconds * 1000;
        const countdown = appState.timers.countdown;
        countdown.inputMinutes = Math.max(1, Math.ceil(result.seconds / 60));
        countdown.totalMs = milliseconds;
        countdown.remainingMs = milliseconds;
        countdown.running = true;
        countdown.targetAt = Date.now() + milliseconds;
        appState.timers.selectedMode = 'countdown';
        appState.markTimersChanged();
        closePalette();
        await runTool('timer');
      } else if (result.kind === 'calculation' && result.value) {
        if (await copyText(result.value)) toast.success(`已复制计算结果：${result.value}`);
        closePalette();
      } else if (result.kind === 'url' && result.value) {
        await openUrl(result.value);
        closePalette();
      } else if (result.kind === 'search' && result.value) {
        await openUrl(`https://www.google.com/search?q=${encodeURIComponent(result.value)}`);
        closePalette();
      }
    } catch (error) {
      toast.error(errorMessage(error, '执行快速操作失败'));
    } finally {
      busy = false;
    }
  }

  function toggleFavorite(event: MouseEvent, result: LauncherResult) {
    event.stopPropagation();
    if (result.toolId) appState.toggleFavorite(result.toolId);
  }

  function handleInput() {
    appState.commandIndex = 0;
  }

  function handleKeydown(event: KeyboardEvent) {
    if (event.key === 'Escape') {
      event.preventDefault();
      closePalette();
    } else if (event.key === 'ArrowDown') {
      event.preventDefault();
      if (results.length) appState.commandIndex = (appState.commandIndex + 1) % results.length;
    } else if (event.key === 'ArrowUp') {
      event.preventDefault();
      if (results.length) appState.commandIndex = (appState.commandIndex - 1 + results.length) % results.length;
    } else if (event.key === 'Enter') {
      event.preventDefault();
      void activate(results[appState.commandIndex]);
    }
  }
</script>

{#if appState.commandOpen}
  <!-- svelte-ignore a11y_click_events_have_key_events -->
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <div class="overlay" onclick={closePalette}>
    <div class="palette" onclick={(event) => event.stopPropagation()}>
      <div class="search-box">
        <span class="material-symbols-rounded">search</span>
        <input bind:this={commandInput} bind:value={appState.commandQuery} oninput={handleInput} onkeydown={handleKeydown}
          placeholder="搜索工具、工作区、网址或输入 > 指令…" autocomplete="off" spellcheck="false" />
        <div class="shortcut">ESC</div>
      </div>

      <div class="command-hints">
        <span>&gt; timer 10m</span><span>&gt; todo 内容</span><span>&gt; workspace 名称</span><span>= (2+3)*4</span>
      </div>

      <div class="results">
        {#each results as result, index (result.id)}
          <!-- svelte-ignore a11y_click_events_have_key_events -->
          <div class="result-item" class:active={index === appState.commandIndex} class:disabled={busy} role="button" tabindex="-1"
            onmousemove={() => appState.commandIndex = index} onclick={() => activate(result)}>
            <div class="icon-wrap {result.accent}"><span class="material-symbols-rounded">{result.icon}</span></div>
            <div class="result-text"><span class="title">{result.title}</span><span class="subtitle">{result.description}</span></div>
            {#if result.kind === 'tool' && result.toolId}
              <button class="favorite" class:active={appState.favorites.includes(result.toolId)}
                onclick={(event) => toggleFavorite(event, result)} aria-label="收藏工具" title="收藏工具">
                <span class="material-symbols-rounded">star</span>
              </button>
            {/if}
            {#if result.shortcut}<div class="cmd-shortcut">{result.shortcut}</div>{/if}
          </div>
        {:else}
          <div class="empty-state">没有找到相关工具或指令</div>
        {/each}
      </div>
      <div class="palette-footer"><span>↑↓ 选择</span><span>Enter 执行</span><span>★ 收藏后优先显示</span></div>
    </div>
  </div>
{/if}

<style>
  .overlay{position:fixed;inset:0;z-index:1200;display:flex;justify-content:center;align-items:flex-start;padding-top:10vh;background:rgba(0,0,0,.42);backdrop-filter:blur(9px);animation:fadeIn .16s ease-out}
  .palette{width:680px;max-width:92vw;background:var(--bg-panel0);border:1px solid var(--border-subtle);border-radius:18px;box-shadow:var(--shadow-lg),0 0 0 1px rgba(255,255,255,.05) inset;overflow:hidden;animation:slideDown .18s cubic-bezier(.2,.8,.2,1)}
  .search-box{display:flex;align-items:center;gap:12px;padding:17px 20px;border-bottom:1px solid var(--border-focus);background:var(--bg-panel1)}.search-box>.material-symbols-rounded{color:var(--text-secondary);font-size:24px}
  input{flex:1;background:transparent;border:none;color:var(--text-primary);font-size:18px;outline:none}input::placeholder{color:var(--text-caption)}
  .shortcut,.cmd-shortcut{font:600 11px/1 ui-monospace,monospace;color:var(--text-caption);background:var(--bg-app);padding:5px 8px;border-radius:6px;border:1px solid var(--border-subtle)}
  .command-hints{display:flex;gap:7px;overflow-x:auto;padding:9px 14px;border-bottom:1px solid var(--border-subtle);background:var(--bg-panel0)}.command-hints span{flex:none;padding:4px 7px;border-radius:6px;background:var(--bg-app);color:var(--text-caption);font:11px ui-monospace,monospace}
  .results{max-height:430px;overflow-y:auto;padding:8px}.result-item{display:flex;align-items:center;gap:14px;width:100%;padding:11px 13px;border-radius:12px;text-align:left;transition:background-color .1s;border:0;background:transparent;cursor:pointer}.result-item.active{background:var(--bg-panel-hover)}.result-item.disabled{opacity:.7;pointer-events:none}
  .icon-wrap{display:grid;place-items:center;width:40px;height:40px;flex:none;border-radius:12px;background:var(--bg-app);border:1px solid var(--border-subtle)}.icon-wrap.teal{color:var(--accent-teal)}.icon-wrap.blue{color:var(--accent-blue)}.icon-wrap.orange{color:#ff9500}.icon-wrap.green{color:#34c759}.icon-wrap.pink{color:#ff2d55}.icon-wrap.purple{color:#af52de}.icon-wrap.red{color:#ff3b30}
  .result-text{display:flex;flex-direction:column;flex:1;min-width:0;gap:3px}.title{font-size:15px;font-weight:600;color:var(--text-primary);overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.subtitle{font-size:12px;color:var(--text-caption);overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
  .favorite{display:grid;place-items:center;width:30px;height:30px;border:0;border-radius:8px;background:transparent;color:var(--text-caption)}.favorite span{font-size:19px;font-variation-settings:'FILL' 0}.favorite.active{color:#ffb000}.favorite.active span{font-variation-settings:'FILL' 1}.favorite:hover{background:var(--bg-app)}
  .empty-state{padding:38px;text-align:center;color:var(--text-caption);font-size:14px}.palette-footer{display:flex;gap:18px;padding:9px 18px;border-top:1px solid var(--border-subtle);color:var(--text-caption);font-size:11px}
  @keyframes fadeIn{from{opacity:0}to{opacity:1}}@keyframes slideDown{from{transform:scale(.98) translateY(-8px);opacity:0}to{transform:scale(1);opacity:1}}
  @media(max-width:600px){.command-hints{display:none}.palette-footer{justify-content:center}.result-item{gap:10px}.cmd-shortcut{display:none}}
</style>
