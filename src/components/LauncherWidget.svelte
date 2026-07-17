<script lang="ts">
  import { appState } from '../state.svelte';
  import { windowTools, type WindowToolId } from '../toolRegistry';

  const launcherTools = windowTools.filter((tool) => tool.showInDock);
  const extraOpenTools = $derived(windowTools.filter((tool) =>
    !tool.showInDock && appState.windows.some((window) => window.toolId === tool.id)
  ));

  function launchTool(id: WindowToolId) {
    appState.openFloatingWindow(id);
  }
</script>

<div class="launcher-widget">
  {#each launcherTools as tool}
    <button class="launcher-btn {tool.accent}" class:running={appState.windows.some((window) => window.toolId === tool.id)} onclick={() => launchTool(tool.id)} title={tool.title}>
      <span class="material-symbols-rounded">{tool.icon}</span>
    </button>
  {/each}
  <button class="launcher-btn blue" onclick={() => appState.activeNavIndex = 1} title="所有应用">
    <span class="material-symbols-rounded">apps</span>
  </button>
  
  <div class="divider"></div>

  {#each extraOpenTools as tool (tool.id)}
    <button class="launcher-btn {tool.accent} running" onclick={() => launchTool(tool.id)} title={tool.title}>
      <span class="material-symbols-rounded">{tool.icon}</span>
    </button>
  {/each}

  {#if extraOpenTools.length}<div class="divider"></div>{/if}

  <button class="launcher-btn gray" onclick={() => appState.settingsOpen = true} title="系统设置">
    <span class="material-symbols-rounded">settings</span>
  </button>
</div>

<style>
  .launcher-widget {
    background-color: var(--bg-panel0, rgba(255, 255, 255, 0.8));
    backdrop-filter: blur(10px);
    border: 1px solid var(--border-subtle, rgba(0, 0, 0, 0.1));
    border-radius: var(--radius-xl, 24px);
    padding: 12px 24px;
    display: flex;
    gap: 16px;
    box-shadow: var(--shadow-md, 0 4px 6px rgba(0,0,0,0.1));
    align-items: center;
    justify-content: center;
  }

  :global([data-theme="dark"]) .launcher-widget {
    background-color: var(--bg-panel0, rgba(30, 30, 30, 0.8));
    border-color: var(--border-subtle, rgba(255, 255, 255, 0.1));
  }

  .launcher-btn {
    width: 48px;
    height: 48px;
    border-radius: 12px;
    border: none;
    display: flex;
    align-items: center;
    justify-content: center;
    cursor: pointer;
    transition: all 0.2s cubic-bezier(0.4, 0, 0.2, 1);
    background: transparent;
    position: relative;
  }

  .launcher-btn:hover {
    transform: translateY(-4px) scale(1.05);
  }

  .launcher-btn.running::after {
    content: '';
    position: absolute;
    bottom: 2px;
    width: 5px;
    height: 5px;
    border-radius: 50%;
    background: currentColor;
  }

  .launcher-btn .material-symbols-rounded {
    font-size: 28px;
  }

  .launcher-btn.teal { color: #30B0C7; }
  .launcher-btn.blue { color: #0A84FF; }
  
  .launcher-btn:hover.teal { background-color: rgba(48, 176, 199, 0.15); }
  .launcher-btn:hover.blue { background-color: rgba(10, 132, 255, 0.15); }
  .launcher-btn:hover.gray { background-color: rgba(128, 128, 128, 0.15); }

  .divider {
    width: 1px;
    height: 32px;
    background-color: var(--border-subtle, rgba(0, 0, 0, 0.1));
    margin: 0 4px;
  }
  
  :global([data-theme="dark"]) .divider {
    background-color: rgba(255, 255, 255, 0.1);
  }
</style>
