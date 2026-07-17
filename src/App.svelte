<script lang="ts">
  import Sidebar from './components/Sidebar.svelte';
  import Topbar from './components/Topbar.svelte';
  import CommandPalette from './components/CommandPalette.svelte';
  import SystemMonitorTile from './components/SystemMonitorTile.svelte';
  import PeekPCWidget from './components/PeekPCWidget.svelte';
  import ScreenTimeView from './components/ScreenTimeView.svelte';
  import HeartRateWidget from './components/HeartRateWidget.svelte';
  import HROverlay from './components/HROverlay.svelte';

  // Desktop widgets
  import ClockWidget from './components/ClockWidget.svelte';
  import TodoWidget from './components/TodoWidget.svelte';
  import PomodoroWidget from './components/PomodoroWidget.svelte';
  import AudioWidget from './components/AudioWidget.svelte';
  import LauncherWidget from './components/LauncherWidget.svelte';
  import FloatingWindow from './components/FloatingWindow.svelte';
  import SettingsModal from './components/SettingsModal.svelte';
  import ToastHost from './components/ToastHost.svelte';
  import LazyToolHost from './components/LazyToolHost.svelte';

  import { appState } from './state.svelte';
  import { runTool } from './tools';
  import { onMount } from 'svelte';
  import { listen } from '@tauri-apps/api/event';
  import { toast } from './toast.svelte';
  import { configureGlobalShortcut } from './desktopIntegration';
  import { windowTools, type WindowToolId } from './toolRegistry';

  let isOverlay = $state(false);

  $effect(() => {
    if (!appState.ready) return;
    appState.activeNavIndex;
    appState.sidebarCollapsed;
    appState.schedulePersist();
  });

  onMount(() => {
    if (window.location.hash === '#/hr-overlay') {
      isOverlay = true;
      return;
    }
    let mounted = true;
    let unlistenPalette: (() => void) | null = null;
    let unlistenPrivacy: (() => void) | null = null;
    const handleGlobalPalette = () => { appState.commandOpen = true; };
    window.addEventListener('congmiao:open-palette', handleGlobalPalette);

    void listen('open-command-palette', () => {
      appState.commandOpen = true;
    }).then((unlisten) => {
      if (mounted) unlistenPalette = unlisten;
      else unlisten();
    });
    void listen<boolean>('peek-privacy-changed', (event) => {
      toast.info(event.payload ? 'Peek PC 隐私模式已开启' : 'Peek PC 隐私模式已关闭');
    }).then((unlisten) => {
      if (mounted) unlistenPrivacy = unlisten;
      else unlisten();
    });

    const handleKeydown = (event: KeyboardEvent) => {
      const withMeta = event.metaKey || event.ctrlKey;

      if (withMeta && event.key.toLowerCase() === 'k') {
        event.preventDefault();
        appState.commandOpen = true;
      }
      if (withMeta && event.key.toLowerCase() === 't') {
        event.preventDefault();
        runTool('timer');
      }
      if (withMeta && event.key.toLowerCase() === 'j') {
        event.preventDefault();
        runTool('json');
      }
    };

    const handleBeforeUnload = () => void appState.persist();
    const handleResize = () => appState.reconcileWindowBounds();
    void appState.hydrate().then(() => {
      if (!mounted) return;
      void configureGlobalShortcut(appState.globalShortcut).catch((error) => {
        console.error('Failed to register global shortcut', error);
        toast.error('全局快捷键注册失败，请在设置中更换组合键');
      });
      window.addEventListener('keydown', handleKeydown);
      window.addEventListener('beforeunload', handleBeforeUnload);
      window.addEventListener('resize', handleResize);
    });
    return () => {
      mounted = false;
      window.removeEventListener('keydown', handleKeydown);
      window.removeEventListener('beforeunload', handleBeforeUnload);
      window.removeEventListener('resize', handleResize);
      window.removeEventListener('congmiao:open-palette', handleGlobalPalette);
      unlistenPalette?.();
      unlistenPrivacy?.();
    };
  });

  function launchToolFromDirectory(id: WindowToolId) {
    void runTool(id);
  }
</script>

{#if isOverlay}
  <HROverlay />
{:else if !appState.ready}
  <div class="workspace-loading"><span class="material-symbols-rounded">progress_activity</span>正在恢复工作区…</div>
{:else}
<div class="app-layout desktop-mode" style="--bg-image: url('{appState.bgImageUrl}'); --bg-blur: {appState.bgBlur}px;">
  
  <div class="desktop-wallpaper"></div>

  <div class="desktop-topbar">
    <Topbar />
  </div>
  
  <main class="desktop-main">
    
    <!-- 桌面小组件层 -->
    <div class="desktop-container" class:hidden={appState.activeNavIndex !== 0}>
      <div class="widgets-layer">
        <div class="widget-col">
          <ClockWidget />
          <HeartRateWidget />
        </div>
        <div class="widget-col">
          <PomodoroWidget />
        </div>
        <div class="widget-col">
          <TodoWidget />
        </div>
      </div>
    </div>

    <!-- 所有应用 (Launchpad) -->
    {#if appState.activeNavIndex === 1}
      <div class="app-drawer-overlay">
        <div class="drawer-header">
          <h2>启动台</h2>
          <button class="back-btn" onclick={() => appState.activeNavIndex = 0}>
            <span class="material-symbols-rounded">close</span>
            返回桌面
          </button>
        </div>
        <div class="tool-directory">
          <div class="dir-grid">
            {#each windowTools.filter((tool) => tool.showInLaunchpad) as tool}
              <button class="tool-card" onclick={() => launchToolFromDirectory(tool.id)}>
                <div class="icon {tool.accent}"><span class="material-symbols-rounded">{tool.icon}</span></div>
                <div class="info"><h4>{tool.title}</h4><p>{tool.description}</p></div>
              </button>
            {/each}
          </div>
        </div>
      </div>
    {:else if appState.activeNavIndex === 2}
      <!-- 使用时长 (Screen Time) -->
      <div class="app-drawer-overlay">
        <div class="drawer-header">
          <h2>使用时长</h2>
          <button class="back-btn" onclick={() => appState.activeNavIndex = 0}>
            <span class="material-symbols-rounded">close</span>
            返回桌面
          </button>
        </div>
        <ScreenTimeView />
      </div>
    {/if}

    <!-- 窗口层 (始终悬浮在桌面和小组件之上) -->
    <div class="windows-layer">
      {#each appState.windows.filter((window) => !window.isMinimized) as win (win.id)}
        <FloatingWindow 
          windowId={win.id}
          toolId={win.toolId}
          title={win.title}
          x={win.x}
          y={win.y}
          width={win.width}
          height={win.height}
          minWidth={win.minWidth}
          minHeight={win.minHeight}
          isMaximized={win.isMaximized}
          zIndex={win.zIndex}
          onClose={() => appState.closeWindow(win.id)}
          onFocus={() => appState.focusWindow(win.id)}
          onMinimize={() => appState.minimizeWindow(win.id)}
          onMaximize={() => appState.toggleWindowMaximize(win.id)}
          onGeometryChange={(geometry) => appState.updateWindowGeometry(win.id, geometry)}
        >
          <LazyToolHost toolId={win.toolId} />
        </FloatingWindow>
      {/each}
    </div>

  </main>

  <!-- 全局底部 Dock 栏 -->
  <div class="launcher-container">
    <LauncherWidget />
  </div>

</div>

<CommandPalette />

{#if appState.settingsOpen}
  <SettingsModal />
{/if}

{/if}

<ToastHost />

<style>
  .workspace-loading {
    display: flex;
    width: 100vw;
    height: 100vh;
    align-items: center;
    justify-content: center;
    gap: 10px;
    color: var(--text-secondary);
    background: var(--bg-app);
  }

  .workspace-loading span { animation: spin 1s linear infinite; }
  @keyframes spin { to { transform: rotate(360deg); } }

  .app-layout {
    display: flex;
    flex-direction: column;
    height: 100vh;
    width: 100vw;
    overflow: hidden;
    background-color: var(--bg-app);
  }

  .app-layout.desktop-mode {
    background-color: #000; /* Fallback */
  }

  .desktop-wallpaper {
    position: absolute;
    inset: -50px;
    background-image: var(--bg-image);
    background-size: cover;
    background-position: center;
    filter: blur(var(--bg-blur));
    z-index: 0;
    pointer-events: none;
  }

  .desktop-topbar {
    z-index: 100;
    /* 让 Topbar 背景半透明化，更像 macOS */
    background: rgba(255, 255, 255, 0.4);
    backdrop-filter: blur(20px);
    border-bottom: 1px solid rgba(0,0,0,0.1);
  }

  :global([data-theme="dark"]) .desktop-topbar {
    background: rgba(0, 0, 0, 0.4);
    border-bottom: 1px solid rgba(255,255,255,0.1);
  }

  /* 覆盖 Topbar 内部样式以适应桌面 */
  :global(.desktop-topbar .topbar) {
    background: transparent !important;
    border: none !important;
    min-height: 60px !important;
  }

  .desktop-main {
    flex: 1;
    position: relative;
    overflow: hidden;
  }

  .desktop-container {
    position: absolute;
    inset: 0;
    overflow: hidden;
    transition: opacity 0.3s;
  }

  .desktop-container.hidden {
    opacity: 0;
    pointer-events: none;
  }

  .widgets-layer {
    padding: 32px;
    display: flex;
    gap: 24px;
    align-items: flex-start;
    height: 100%;
    overflow-y: auto;
  }

  .widget-col {
    display: flex;
    flex-direction: column;
    gap: 24px;
    width: 320px;
  }

  .launcher-container {
    position: absolute;
    bottom: 24px;
    left: 50%;
    transform: translateX(-50%);
    z-index: 200;
  }

  .windows-layer {
    position: absolute;
    inset: 0;
    pointer-events: none;
    z-index: 50;
  }

  :global(.floating-window) {
    pointer-events: auto;
  }

  /* Launchpad / App Drawer */
  .app-drawer-overlay {
    position: absolute;
    inset: 0;
    background: rgba(255, 255, 255, 0.7);
    backdrop-filter: blur(40px);
    z-index: 40;
    display: flex;
    flex-direction: column;
    padding: 40px;
    overflow-y: auto;
    animation: fadeIn 0.2s ease-out;
  }

  :global([data-theme="dark"]) .app-drawer-overlay {
    background: rgba(0, 0, 0, 0.7);
  }

  @keyframes fadeIn {
    from { opacity: 0; transform: scale(0.98); }
    to { opacity: 1; transform: scale(1); }
  }

  .drawer-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 40px;
    max-width: 1200px;
    width: 100%;
    margin-left: auto;
    margin-right: auto;
  }

  .drawer-header h2 {
    font-size: 32px;
    font-weight: 700;
    color: var(--text-primary);
  }

  .back-btn {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 10px 20px;
    border-radius: 99px;
    border: none;
    background: var(--bg-panel0);
    color: var(--text-primary);
    font-weight: 600;
    cursor: pointer;
    box-shadow: var(--shadow-sm);
    transition: all 0.2s;
  }

  .back-btn:hover {
    transform: translateY(-2px);
    box-shadow: var(--shadow-md);
  }

  .tool-directory {
    max-width: 1200px;
    margin: 0 auto;
    width: 100%;
    padding-bottom: 100px; /* Space for dock */
  }

  .dir-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(320px, 1fr));
    gap: 24px;
  }

  .tool-card {
    display: flex;
    align-items: center;
    gap: 16px;
    padding: 20px;
    background-color: var(--bg-panel0);
    border: 1px solid var(--border-subtle);
    border-radius: var(--radius-lg);
    text-align: left;
    transition: all 0.2s cubic-bezier(0.4, 0, 0.2, 1);
    cursor: pointer;
  }

  .tool-card:hover {
    transform: translateY(-4px);
    box-shadow: var(--shadow-md);
    border-color: var(--border-focus);
  }

  .tool-card .icon {
    display: grid;
    place-items: center;
    width: 56px;
    height: 56px;
    border-radius: 16px;
    flex-shrink: 0;
  }

  .tool-card .icon.orange { color: #FF9500; background-color: rgba(255, 149, 0, 0.15); }
  .tool-card .icon.blue { color: #0A84FF; background-color: rgba(10, 132, 255, 0.15); }
  .tool-card .icon.green { color: #34C759; background-color: rgba(52, 199, 89, 0.15); }
  .tool-card .icon.pink { color: #FF2D55; background-color: rgba(255, 45, 85, 0.15); }
  .tool-card .icon.purple { color: #AF52DE; background-color: rgba(175, 82, 222, 0.15); }
  .tool-card .icon.red { color: #FF3B30; background-color: rgba(255, 59, 48, 0.15); }
  .tool-card .icon.teal { color: #30B0C7; background-color: rgba(48, 176, 199, 0.15); }

  .tool-card .icon span {
    font-size: 28px;
  }

  .tool-card .info {
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .tool-card .info h4 {
    font-size: 16px;
    font-weight: 600;
    color: var(--text-primary);
  }

  .tool-card .info p {
    font-size: 13px;
    color: var(--text-secondary);
    line-height: 1.4;
  }
</style>
