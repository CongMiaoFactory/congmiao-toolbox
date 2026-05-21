<script lang="ts">
  import { getVersion } from '@tauri-apps/api/app';
  import { ask, message } from '@tauri-apps/plugin-dialog';
  import { disable, enable, isEnabled } from '@tauri-apps/plugin-autostart';
  import { relaunch } from '@tauri-apps/plugin-process';
  import { check, type Update } from '@tauri-apps/plugin-updater';
  import { onDestroy, onMount } from 'svelte';
  import { appState } from '../state.svelte';
  import { invoke } from '@tauri-apps/api/core';
  import { listen } from '@tauri-apps/api/event';

  let autostartEnabled = $state<boolean | null>(null);
  let autostartBusy = $state(false);
  let updateBusy = $state(false);
  let updatePendingVersion = $state<string | null>(null);
  let updateStatusText = $state('检查更新');
  let pendingUpdate = $state<Update | null>(null);

  // 媒体状态
  let isPlaying = $state(false);
  let currentSong = $state('暂无播放');
  let currentArtist = $state('未知');
  let unlistenMedia: (() => void) | null = null;

  const closePendingUpdate = async () => {
    if (!pendingUpdate) return;
    try {
      await pendingUpdate.close();
    } catch (error) {
      console.error(error);
    }
    pendingUpdate = null;
  };

  const refreshDesktopState = async () => {
    appState.appVersion = await getVersion();
    autostartEnabled = await isEnabled();
  };

  const syncUpdate = async (interactive = false) => {
    if (updateBusy) return;
    updateBusy = true;
    updateStatusText = '检查中...';

    try {
      await closePendingUpdate();
      const update = await check();
      if (update) {
        pendingUpdate = update;
        updatePendingVersion = update.version;
        updateStatusText = '可安装更新';
        appState.addActivity({
          source: 'SYSTEM',
          title: 'Update Ready',
          value: `发现新版本 v${update.version}`,
          accent: 'teal',
        });
        if (interactive) await installPendingUpdate();
      } else {
        updatePendingVersion = null;
        updateStatusText = '已是最新';
        if (interactive) {
          await message(`当前已经是最新版本 v${appState.appVersion}。`, {
            title: '检查更新',
            kind: 'info',
          });
        }
      }
    } catch (error) {
      console.error(error);
      updatePendingVersion = null;
      updateStatusText = interactive ? '更新失败' : '检查更新';
      if (interactive) {
        await message('检查更新失败，请稍后再试。', {
          title: '检查更新',
          kind: 'error',
        });
      }
    } finally {
      updateBusy = false;
    }
  };

  const installPendingUpdate = async () => {
    if (!pendingUpdate || updateBusy) return;
    const shouldInstall = await ask(
      `发现新版本 v${pendingUpdate.version}，要现在下载并安装吗？`,
      {
        title: '版本更新',
        kind: 'info',
        okLabel: '立即更新',
        cancelLabel: '稍后再说',
      }
    );
    if (!shouldInstall) return;

    updateBusy = true;
    updateStatusText = '下载中...';

    try {
      await pendingUpdate.downloadAndInstall((event) => {
        if (event.event === 'Started') updateStatusText = '开始下载';
        if (event.event === 'Progress') updateStatusText = '正在下载';
        if (event.event === 'Finished') updateStatusText = '正在安装';
      });
      appState.addActivity({
        source: 'SYSTEM',
        title: 'Update Installed',
        value: `已安装 v${pendingUpdate.version}`,
        accent: 'teal',
      });
      const shouldRestart = await ask(
        '更新已经安装完成，是否现在重启应用？',
        {
          title: '版本更新',
          kind: 'info',
          okLabel: '立即重启',
          cancelLabel: '稍后手动重启',
        }
      );
      updatePendingVersion = null;
      updateStatusText = shouldRestart ? '正在重启' : '重启后生效';
      await closePendingUpdate();
      if (shouldRestart) await relaunch();
    } catch (error) {
      console.error(error);
      updateStatusText = '安装失败';
      await message('下载或安装更新失败，请稍后再试。', {
        title: '版本更新',
        kind: 'error',
      });
    } finally {
      updateBusy = false;
    }
  };

  const handleUpdateClick = async () => {
    if (updatePendingVersion) {
      await installPendingUpdate();
      return;
    }
    await syncUpdate(true);
  };

  const toggleAutostart = async () => {
    if (autostartBusy || autostartEnabled === null) return;
    autostartBusy = true;

    try {
      if (autostartEnabled) {
        await disable();
        autostartEnabled = false;
      } else {
        await enable();
        autostartEnabled = true;
      }
    } catch (error) {
      console.error(error);
    } finally {
      autostartBusy = false;
    }
  };

  onMount(async () => {
    await refreshDesktopState();
    await syncUpdate(false);
    
    unlistenMedia = await listen<{title: string, artist: string, is_playing: boolean}>('media-update', (event) => {
      const payload = event.payload;
      currentSong = payload.title || '暂无播放';
      currentArtist = payload.artist || '未知';
      isPlaying = payload.is_playing;
    });
  });

  onDestroy(() => {
    void closePendingUpdate();
    if (unlistenMedia) unlistenMedia();
  });

  async function mediaPrev() { await invoke('media_prev'); }
  async function mediaToggle() { await invoke('media_play_pause'); }
  async function mediaNext() { await invoke('media_next'); }
</script>

<header class="mac-menubar">
  <div class="menubar-left">
    <div class="logo-item" title="Congmiao Toolbox">
      <img src="/tauri.svg" alt="Logo" class="mini-logo" />
    </div>
    <div class="menu-item bold">Congmiao</div>
    <button class="menu-item menu-btn" onclick={() => appState.activeNavIndex = 1}>应用</button>
    <button class="menu-item menu-btn" onclick={() => appState.activeNavIndex = 2}>统计</button>
    <button class="menu-item menu-btn" onclick={() => appState.commandOpen = true}>搜索</button>
  </div>

  <!-- 中间的媒体控制区 -->
  <div class="media-mini-player">
    <button class="media-btn" onclick={mediaPrev} aria-label="上一首"><span class="material-symbols-rounded">skip_previous</span></button>
    <button class="media-btn" onclick={mediaToggle} aria-label={isPlaying ? '暂停' : '播放'}><span class="material-symbols-rounded">{isPlaying ? 'pause' : 'play_arrow'}</span></button>
    <button class="media-btn" onclick={mediaNext} aria-label="下一首"><span class="material-symbols-rounded">skip_next</span></button>
    <div class="media-info" title="{currentSong} - {currentArtist}">
      <span class="media-title">{currentSong}</span>
      <span class="media-artist">- {currentArtist}</span>
    </div>
  </div>

  <div class="menubar-right">
    {#if updateBusy}
      <div class="status-icon" title={updateStatusText}>
        <span class="material-symbols-rounded rotating">sync</span>
      </div>
    {:else if updatePendingVersion}
      <button class="status-icon highlight" onclick={handleUpdateClick} title="有新版本 v{updatePendingVersion}">
        <span class="material-symbols-rounded">system_update_alt</span>
      </button>
    {/if}

    <button 
      class="status-icon {autostartEnabled ? 'active' : ''}" 
      onclick={toggleAutostart} 
      title={autostartEnabled ? '开机自启已开启' : '开机自启未开启'}
      disabled={autostartBusy}
    >
      <span class="material-symbols-rounded">rocket_launch</span>
    </button>

    <div class="status-icon text-only" title="当前版本">v{appState.appVersion}</div>

    <button class="status-icon" onclick={() => appState.toggleTheme()} title="切换暗色/亮色模式">
      <span class="material-symbols-rounded">{appState.theme === 'dark' ? 'light_mode' : 'dark_mode'}</span>
    </button>
  </div>
</header>

<style>
  .mac-menubar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    height: 28px;
    padding: 0 16px;
    background: rgba(255, 255, 255, 0.4);
    backdrop-filter: blur(20px);
    -webkit-backdrop-filter: blur(20px);
    color: var(--text-primary, #333);
    font-size: 13px;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    user-select: none;
    flex-shrink: 0;
    position: relative;
  }

  :global([data-theme="dark"]) .mac-menubar {
    background: rgba(0, 0, 0, 0.4);
    color: var(--text-primary, #eee);
  }

  .menubar-left, .menubar-right {
    display: flex;
    align-items: center;
    height: 100%;
  }

  .menubar-left {
    gap: 12px;
  }

  .menubar-right {
    gap: 16px;
  }

  .logo-item {
    display: flex;
    align-items: center;
    justify-content: center;
    height: 100%;
    cursor: pointer;
  }

  .mini-logo {
    width: 14px;
    height: 14px;
    object-fit: contain;
  }

  .menu-item {
    cursor: pointer;
    font-weight: 500;
    transition: color 0.1s;
    height: 100%;
    display: flex;
    align-items: center;
  }

  .menu-item.bold {
    font-weight: 700;
  }

  .menu-item:hover {
    color: var(--accent-blue, #0A84FF);
  }

  .status-icon {
    display: flex;
    align-items: center;
    justify-content: center;
    background: transparent;
    border: none;
    color: inherit;
    cursor: pointer;
    padding: 0;
    height: 100%;
    font-size: 13px;
    font-weight: 500;
  }

  .status-icon .material-symbols-rounded {
    font-size: 16px;
  }

  .status-icon.text-only {
    cursor: default;
    color: var(--text-secondary, #666);
  }

  :global([data-theme="dark"]) .status-icon.text-only {
    color: var(--text-secondary, #aaa);
  }

  .status-icon:not(.text-only):hover {
    color: var(--accent-blue, #0A84FF);
  }

  .status-icon.active {
    color: #34C759;
  }

  .status-icon.highlight {
    color: #FF9500;
  }

  .rotating {
    animation: rotate 2s linear infinite;
  }

  @keyframes rotate {
    from { transform: rotate(0deg); }
    to { transform: rotate(360deg); }
  }

  .media-mini-player {
    display: flex;
    align-items: center;
    gap: 4px;
    position: absolute;
    left: 50%;
    transform: translateX(-50%);
    height: 100%;
  }

  .media-btn {
    background: transparent;
    border: none;
    color: inherit;
    cursor: pointer;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 0;
    width: 24px;
    height: 24px;
    border-radius: 4px;
    transition: background-color 0.2s;
  }
  .media-btn:hover {
    background-color: var(--bg-panel-hover, rgba(0,0,0,0.05));
    color: var(--accent-blue, #0A84FF);
  }
  :global([data-theme="dark"]) .media-btn:hover { background-color: rgba(255,255,255,0.1); }
  .media-btn .material-symbols-rounded { font-size: 16px; }

  .media-info {
    display: flex;
    align-items: baseline;
    gap: 4px;
    margin-left: 6px;
    max-width: 200px;
    overflow: hidden;
    white-space: nowrap;
    text-overflow: ellipsis;
  }

  .media-title {
    font-weight: 600;
    font-size: 13px;
  }

  .media-artist {
    font-size: 12px;
    color: var(--text-secondary, #666);
  }
  :global([data-theme="dark"]) .media-artist { color: var(--text-secondary, #aaa); }

  .menu-btn {
    background: transparent;
    border: none;
    color: inherit;
    font-size: inherit;
    font-family: inherit;
    padding: 0;
  }
</style>
