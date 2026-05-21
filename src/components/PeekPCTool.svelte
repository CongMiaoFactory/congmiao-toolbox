<script lang="ts">
  import { invoke } from '@tauri-apps/api/core';
  import { onDestroy, onMount } from 'svelte';
  import { open } from '@tauri-apps/plugin-dialog';
  import { copyText } from '../tools';

  interface MemoryInfo {
    total: number;
    used: number;
    available: number;
    used_percent: number;
  }

  interface ForegroundWindowInfo {
    title: string;
    process_name: string;
    process_id: number;
  }

  interface PeekStatusResponse {
    status: string;
    cpu: number;
    memory: MemoryInfo;
    foreground_window: ForegroundWindowInfo | null;
    media: { title: string; artist: string; is_playing: boolean } | null;
  }

  const emptyStatus: PeekStatusResponse = {
    status: 'idle',
    cpu: 0,
    memory: {
      total: 0,
      used: 0,
      available: 0,
      used_percent: 0
    },
    foreground_window: null,
    media: null
  };

  let isRunning = $state(false);
  let isPrivacyEnabled = $state(false);
  let privacyImagePath = $state<string | null>(null);
  let isToggling = $state(false);
  let serverUrl = $state('http://127.0.0.1:3000');
  let peekStatus = $state<PeekStatusResponse>(emptyStatus);
  let statusTimer: ReturnType<typeof setInterval> | undefined;

  const screenshotUrl = $derived(`${serverUrl}/api/screenshot`);
  const statusUrl = $derived(`${serverUrl}/api/status`);

  const formatMegabytes = (value: number) => {
    if (!value) return '--';
    if (value >= 1024) return `${(value / 1024).toFixed(1)} GB`;
    return `${value.toFixed(0)} MB`;
  };

  const refreshServerUrl = async () => {
    serverUrl = await invoke<string>('get_peek_server_url');
  };

  const checkStatus = async () => {
    isRunning = await invoke<boolean>('get_peek_status');
    isPrivacyEnabled = await invoke<boolean>('get_privacy_status');

    if (!isRunning) {
      peekStatus = emptyStatus;
      return;
    }

    await refreshServerUrl();

    try {
      const resp = await fetch(statusUrl);
      if (!resp.ok) throw new Error(`Unexpected status: ${resp.status}`);
      peekStatus = await resp.json();
    } catch (error) {
      console.error(error);
      peekStatus = emptyStatus;
    }
  };

  onMount(async () => {
    await refreshServerUrl();
    await checkStatus();
    statusTimer = setInterval(checkStatus, 3000);
  });

  onDestroy(() => {
    if (statusTimer) clearInterval(statusTimer);
  });

  const handleToggleServer = async () => {
    if (isToggling) return;
    isToggling = true;

    try {
      if (isRunning) {
        await invoke('stop_peek_server');
        isRunning = false;
        peekStatus = emptyStatus;
      } else {
        serverUrl = await invoke<string>('start_peek_server');
        isRunning = true;
        await checkStatus();
      }
    } catch (error) {
      console.error(error);
    }

    isToggling = false;
  };

  const handleTogglePrivacy = async () => {
    isPrivacyEnabled = await invoke<boolean>('toggle_privacy');
  };

  const handleSelectImage = async () => {
    const selected = await open({
      multiple: false,
      filters: [{ name: 'Images', extensions: ['png', 'jpg', 'jpeg', 'webp'] }]
    });

    if (selected && typeof selected === 'string') {
      privacyImagePath = selected;
      await invoke('set_peek_privacy_image', { path: selected });
    }
  };

  const handleClearImage = async () => {
    privacyImagePath = null;
    await invoke('set_peek_privacy_image', { path: null });
  };

  const handleCopyUrl = async (value: string) => {
    await copyText(value);
  };
</script>

<div class="tool-content">
  <div class="tool-header">
    <div class="icon blue">
      <span class="material-symbols-rounded">cast</span>
    </div>
    <div class="title-meta">
      <h3>Peek PC 遥控监控</h3>
      <p>现在默认输出模糊化截图，并同步前台窗口状态。{isRunning ? '服务已启动' : '服务未运行'}</p>
    </div>
  </div>

  <div class="control-grid">
    <div class="card status-card" class:active={isRunning}>
      <div class="card-title">
        <span class="material-symbols-rounded">sensors</span>
        服务状态
      </div>

      <div class="endpoint-block">
        <span class="label">访问地址</span>
        <div class="code-row">
          <code>{serverUrl}</code>
          <button class="mini-btn" onclick={() => handleCopyUrl(serverUrl)}>复制</button>
        </div>
      </div>

      <button class="toggle-btn" onclick={handleToggleServer}>
        <span class="material-symbols-rounded">{isRunning ? 'stop_circle' : 'play_circle'}</span>
        {isRunning ? '停止服务端' : '启动服务端'}
      </button>
    </div>

    <div class="card settings-card">
      <div class="card-title">
        <span class="material-symbols-rounded">visibility_off</span>
        隐私模式
      </div>

      <div class="setting-row">
        <span>启用隐私遮罩</span>
        <button class="switch" class:on={isPrivacyEnabled} onclick={handleTogglePrivacy} title="切换隐私遮罩" aria-label="切换隐私遮罩">
          <div class="knob"></div>
        </button>
      </div>

      <div class="privacy-note">
        常规截图已经默认模糊；开启隐私模式后会进一步加重模糊，或直接返回你设置的替代图片。
      </div>

      <div class="image-selector">
        <span class="label">自定义隐私图片</span>
        {#if privacyImagePath}
          <div class="path-box">
            <span class="path">{privacyImagePath.split('/').pop()}</span>
            <button class="clear-btn" onclick={handleClearImage}>
              <span class="material-symbols-rounded">close</span>
            </button>
          </div>
        {:else}
          <button class="outline-btn" onclick={handleSelectImage}>
            <span class="material-symbols-rounded">add_photo_alternate</span>
            选择图片
          </button>
        {/if}
      </div>
    </div>

    <div class="card monitor-card">
      <div class="card-title">
        <span class="material-symbols-rounded">monitoring</span>
        系统状态
      </div>

      <div class="metric-grid">
        <div class="metric">
          <span class="metric-label">CPU</span>
          <strong>{peekStatus.cpu.toFixed(1)}%</strong>
        </div>
        <div class="metric">
          <span class="metric-label">内存占用</span>
          <strong>{peekStatus.memory.used_percent.toFixed(1)}%</strong>
        </div>
        <div class="metric wide">
          <span class="metric-label">已用 / 总量</span>
          <strong>{formatMegabytes(peekStatus.memory.used)} / {formatMegabytes(peekStatus.memory.total)}</strong>
        </div>
        <div class="metric wide">
          <span class="metric-label">可用内存</span>
          <strong>{formatMegabytes(peekStatus.memory.available)}</strong>
        </div>
      </div>

      <div class="window-card">
        <span class="label">前台窗口</span>
        {#if peekStatus.foreground_window}
          <strong class="window-title">{peekStatus.foreground_window.title || '未命名窗口'}</strong>
          <span class="window-meta">
            {peekStatus.foreground_window.process_name || '未知进程'} · PID {peekStatus.foreground_window.process_id}
          </span>
        {:else}
          <span class="window-empty">当前暂时获取不到前台窗口信息</span>
        {/if}
      </div>

      <div class="window-card media-card">
        <span class="label">当前媒体</span>
        {#if peekStatus.media}
          <div class="media-header">
            <span class="material-symbols-rounded icon-media">
              {peekStatus.media.is_playing ? 'play_circle' : 'pause_circle'}
            </span>
            <strong class="window-title">{peekStatus.media.title || '未知媒体'}</strong>
          </div>
          <span class="window-meta">
            {peekStatus.media.artist || '未知艺术家'}
          </span>
        {:else}
          <span class="window-empty">当前无媒体播放</span>
        {/if}
      </div>
    </div>

    <div class="card endpoint-card">
      <div class="card-title">
        <span class="material-symbols-rounded">image</span>
        接口概览
      </div>

      <div class="endpoint-block">
        <span class="label">截图接口</span>
        <div class="code-row">
          <code>{screenshotUrl}</code>
          <button class="mini-btn" onclick={() => handleCopyUrl(screenshotUrl)}>复制</button>
        </div>
      </div>

      <div class="endpoint-block">
        <span class="label">状态接口</span>
        <div class="code-row">
          <code>{statusUrl}</code>
          <button class="mini-btn" onclick={() => handleCopyUrl(statusUrl)}>复制</button>
        </div>
      </div>

      <p class="endpoint-note">
        这版参考了 `Peek-PC-2.0` 的状态接口思路，补上了前台窗口信息；截图则固定为默认模糊输出，不再暴露额外调参。
      </p>
    </div>
  </div>

  <div class="tip-box">
    <span class="material-symbols-rounded">info</span>
    <p>截图接口现在默认会先缩放再模糊，并带有短时缓存，适合被局域网设备连续轮询。</p>
  </div>
</div>

<style>
  .tool-content {
    display: flex;
    flex-direction: column;
    gap: 32px;
    max-width: 980px;
  }

  .tool-header {
    display: flex;
    align-items: center;
    gap: 20px;
  }

  .icon {
    display: grid;
    place-items: center;
    width: 48px;
    height: 48px;
    border-radius: 14px;
  }

  .icon.blue {
    background-color: rgba(10, 132, 255, 0.15);
    color: #0A84FF;
  }

  .title-meta h3 { margin: 0; font-size: 20px; font-weight: 700; color: var(--text-primary); }
  .title-meta p { margin: 4px 0 0; font-size: 14px; color: var(--text-secondary); }

  .control-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
    gap: 20px;
  }

  .card {
    background-color: var(--bg-panel0);
    border: 1px solid var(--border-subtle);
    border-radius: 20px;
    padding: 24px;
    display: flex;
    flex-direction: column;
    gap: 18px;
  }

  .card-title {
    display: flex;
    align-items: center;
    gap: 8px;
    font-size: 14px;
    font-weight: 700;
    color: var(--text-primary);
  }

  .card-title .material-symbols-rounded { font-size: 18px; color: var(--text-secondary); }

  .label {
    font-size: 12px;
    font-weight: 600;
    color: var(--text-caption);
    text-transform: uppercase;
  }

  .endpoint-block {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .code-row {
    display: flex;
    gap: 10px;
    align-items: center;
  }

  code {
    flex: 1;
    min-width: 0;
    background: var(--bg-panel1);
    padding: 12px;
    border-radius: 12px;
    font-family: ui-monospace, SFMono-Regular, monospace;
    font-size: 13px;
    color: #0A84FF;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .mini-btn {
    flex-shrink: 0;
    padding: 10px 12px;
    border: 1px solid var(--border-subtle);
    border-radius: 12px;
    background: var(--bg-panel1);
    color: var(--text-secondary);
    font-size: 12px;
    font-weight: 700;
    cursor: pointer;
    transition: all 0.2s;
  }

  .mini-btn:hover {
    color: var(--text-primary);
    border-color: var(--border-focus);
  }

  .toggle-btn {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 8px;
    padding: 14px;
    background-color: #0A84FF;
    color: white;
    border: none;
    border-radius: 14px;
    font-weight: 700;
    cursor: pointer;
    transition: all 0.2s;
  }

  .toggle-btn:hover { background-color: #0070e0; transform: translateY(-1px); }
  .status-card.active .toggle-btn { background-color: rgba(255, 59, 48, 0.1); color: #FF3B30; }

  .setting-row {
    display: flex;
    justify-content: space-between;
    align-items: center;
    font-size: 14px;
    font-weight: 600;
    color: var(--text-secondary);
  }

  .switch {
    position: relative;
    width: 44px;
    height: 24px;
    background-color: var(--bg-panel1);
    border-radius: 12px;
    border: 1px solid var(--border-subtle);
    cursor: pointer;
    transition: 0.3s cubic-bezier(0.18, 0.89, 0.32, 1.28);
  }

  .switch.on { background-color: #34C759; border-color: #34C759; }

  .knob {
    position: absolute;
    top: 3px;
    left: 3px;
    width: 16px;
    height: 16px;
    background-color: white;
    border-radius: 50%;
    box-shadow: 0 1px 3px rgba(0,0,0,0.2);
    transition: transform 0.3s cubic-bezier(0.18, 0.89, 0.32, 1.28);
  }

  .switch.on .knob { transform: translateX(20px); }

  .privacy-note {
    font-size: 13px;
    line-height: 1.6;
    color: var(--text-secondary);
    background: var(--bg-panel1);
    border-radius: 14px;
    padding: 12px 14px;
  }

  .image-selector {
    display: flex;
    flex-direction: column;
    gap: 10px;
  }

  .outline-btn {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 8px;
    padding: 10px;
    background: transparent;
    border: 1px dashed var(--border-subtle);
    border-radius: 12px;
    color: var(--text-secondary);
    font-size: 13px;
    font-weight: 600;
    cursor: pointer;
    transition: all 0.2s;
  }

  .outline-btn:hover { background: var(--bg-panel1); border-color: var(--border-focus); color: var(--text-primary); }

  .path-box {
    display: flex;
    align-items: center;
    justify-content: space-between;
    background: var(--bg-panel1);
    padding: 8px 12px;
    border-radius: 10px;
    font-size: 13px;
  }

  .path {
    color: var(--text-primary);
    font-weight: 500;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    max-width: 180px;
  }

  .clear-btn {
    background: transparent;
    border: none;
    color: var(--text-caption);
    cursor: pointer;
    display: flex;
  }

  .clear-btn:hover { color: #FF3B30; }

  .metric-grid {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 12px;
  }

  .metric {
    display: flex;
    flex-direction: column;
    gap: 6px;
    padding: 14px;
    border-radius: 14px;
    background: var(--bg-panel1);
  }

  .metric.wide { grid-column: span 2; }
  .metric-label { font-size: 12px; color: var(--text-caption); text-transform: uppercase; }
  .metric strong { font-size: 16px; color: var(--text-primary); }

  .window-card {
    display: flex;
    flex-direction: column;
    gap: 8px;
    padding: 16px;
    border-radius: 16px;
    background: linear-gradient(135deg, rgba(10, 132, 255, 0.07), rgba(10, 132, 255, 0.02));
    border: 1px solid rgba(10, 132, 255, 0.1);
  }

  .window-title {
    font-size: 15px;
    color: var(--text-primary);
    line-height: 1.4;
  }

  .window-meta,
  .window-empty,
  .endpoint-note {
    font-size: 13px;
    color: var(--text-secondary);
    line-height: 1.6;
  }

  .media-header {
    display: flex;
    align-items: center;
    gap: 6px;
  }
  
  .icon-media {
    font-size: 18px;
    color: var(--text-secondary);
  }

  .tip-box {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 16px;
    background-color: rgba(10, 132, 255, 0.05);
    border-radius: 16px;
    border: 1px solid rgba(10, 132, 255, 0.1);
  }

  .tip-box .material-symbols-rounded { color: #0A84FF; font-size: 20px; }
  .tip-box p { margin: 0; font-size: 13px; color: var(--text-secondary); line-height: 1.5; }
</style>
