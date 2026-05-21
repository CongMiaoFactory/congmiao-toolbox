<script lang="ts">
  import { invoke } from '@tauri-apps/api/core';
  import { listen } from '@tauri-apps/api/event';
  import { onMount, onDestroy } from 'svelte';

  let bpm = $state(0);
  let connected = $state(false);
  let isScanning = $state(false);
  let showSettings = $state(false);
  let deviceFilter = $state('');
  let statusTimer: ReturnType<typeof setInterval>;
  let unlisten: (() => void) | null = null;

  let pulseInterval = $derived(bpm > 0 ? (60000 / bpm) : 1000);

  onMount(async () => {
    unlisten = await listen<number>('hr-update', (event) => {
      bpm = event.payload;
    });

    deviceFilter = await invoke<string>('get_hr_device_filter');

    const check = async () => {
      const s = await invoke<{bpm: number; connected: boolean}>('get_hr_status');
      connected = s.connected;
      if (s.bpm > 0) bpm = s.bpm;
    };
    await check();
    statusTimer = setInterval(check, 3000);
  });

  onDestroy(() => {
    if (unlisten) unlisten();
    if (statusTimer) clearInterval(statusTimer);
  });

  const handleToggle = async () => {
    if (connected || isScanning) {
      await invoke('stop_hr_scan');
      connected = false;
      isScanning = false;
      bpm = 0;
    } else {
      isScanning = true;
      await invoke('start_hr_scan');
    }
  };

  const handlePopOut = async () => {
    await invoke('open_hr_overlay');
  };

  const handleSaveFilter = async () => {
    await invoke('set_hr_device_filter', { filter: deviceFilter });
    showSettings = false;
  };
</script>

<div class="bento-card">
  {#if showSettings}
    <!-- Settings Panel -->
    <div class="settings-panel">
      <div class="settings-header">
        <h4>设备过滤</h4>
        <button class="close-btn" onclick={() => showSettings = false}>
          <span class="material-symbols-rounded">close</span>
        </button>
      </div>
      <label class="filter-label" for="hr-device-filter">设备名称或蓝牙地址</label>
      <input
        id="hr-device-filter"
        class="filter-input"
        type="text"
        placeholder="例: Polar H10 / AA:BB:CC"
        bind:value={deviceFilter}
      />
      <p class="hint">留空则自动连接第一个心率设备</p>
      <button class="save-btn" onclick={handleSaveFilter}>
        <span class="material-symbols-rounded">check</span>
        保存
      </button>
    </div>
  {:else}
    <!-- Main View -->
    <div class="card-header">
      <div class="title-row">
        <div class="icon-wrap red">
          <svg
            class="heart-svg"
            class:beating={bpm > 0}
            style="animation-duration: {pulseInterval}ms"
            viewBox="0 0 24 24"
            fill="currentColor"
            xmlns="http://www.w3.org/2000/svg"
          >
            <path d="M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z"/>
          </svg>
        </div>
        <div class="text-col">
          <h4>心率监控</h4>
          <span class="status" class:on={connected}>
            <span class="dot"></span>
            {#if connected}已连接{:else if isScanning}扫描中…{:else}未连接{/if}
          </span>
        </div>
      </div>
      <button class="gear-btn" onclick={() => showSettings = true} title="设备设置">
        <span class="material-symbols-rounded">settings</span>
      </button>
    </div>

    <div class="bpm-display">
      <span class="bpm-number">{bpm > 0 ? bpm : '--'}</span>
      <span class="bpm-unit">bpm</span>
    </div>

    <div class="card-actions">
      <button class="action-btn" class:danger={connected || isScanning} onclick={handleToggle}>
        <span class="material-symbols-rounded">{connected || isScanning ? 'bluetooth_disabled' : 'bluetooth_searching'}</span>
        <span>{connected ? '断开' : isScanning ? '停止' : '连接'}</span>
      </button>
      <button class="action-btn pop-btn" onclick={handlePopOut} title="弹出独立窗口">
        <span class="material-symbols-rounded">open_in_new</span>
      </button>
    </div>
  {/if}
</div>

<style>
  .bento-card {
    background-color: var(--bg-panel0);
    border: 1px solid var(--border-subtle);
    border-radius: 16px;
    padding: 16px;
    display: flex;
    flex-direction: column;
    justify-content: space-between;
    gap: 8px;
    box-shadow: var(--shadow-sm);
    transition: transform 0.2s, box-shadow 0.2s;
    position: relative;
    overflow: hidden;
  }

  .bento-card:hover { box-shadow: var(--shadow-md); transform: translateY(-2px); }

  .card-header { display: flex; justify-content: space-between; align-items: flex-start; }
  .title-row { display: flex; align-items: center; gap: 10px; }
  .text-col { display: flex; flex-direction: column; }

  .icon-wrap { display: grid; place-items: center; width: 32px; height: 32px; border-radius: 10px; }
  .icon-wrap.red { background-color: rgba(255, 59, 48, 0.15); color: #FF3B30; }

  h4 { font-size: 13px; font-weight: 600; color: var(--text-primary); margin: 0; }

  .status { font-size: 11px; color: var(--text-caption); display: flex; align-items: center; gap: 4px; margin-top: 2px; }
  .dot { width: 6px; height: 6px; border-radius: 50%; background-color: var(--text-caption); }
  .status.on .dot { background-color: #34C759; box-shadow: 0 0 4px rgba(52, 199, 89, 0.8); }
  .status.on { color: #34C759; }

  .gear-btn {
    display: grid; place-items: center; width: 28px; height: 28px; border-radius: 8px;
    background: transparent; border: none; color: var(--text-caption); cursor: pointer; transition: all 0.2s;
  }
  .gear-btn:hover { background-color: var(--bg-panel1); color: var(--text-primary); }
  .gear-btn .material-symbols-rounded { font-size: 16px; }

  .heart-svg {
    width: 20px;
    height: 20px;
    transition: color 0.2s;
  }

  .heart-svg.beating {
    animation: heartbeat 1s ease-in-out infinite;
    color: #FF3B30;
  }

  @keyframes heartbeat {
    0%, 100% { transform: scale(1); }
    12% { transform: scale(1.3); }
    24% { transform: scale(0.95); }
    36% { transform: scale(1.15); }
    48% { transform: scale(1); }
  }

  .bpm-display { display: flex; align-items: baseline; gap: 4px; justify-content: center; padding: 8px 0; }
  .bpm-number { font-size: 36px; font-weight: 700; color: var(--text-primary); letter-spacing: -0.03em; line-height: 1; }
  .bpm-unit { font-size: 14px; font-weight: 600; color: var(--text-caption); }

  .card-actions { display: flex; gap: 6px; }
  .action-btn {
    display: flex; align-items: center; justify-content: center; gap: 4px;
    flex: 1; padding: 6px 0; background-color: rgba(255, 59, 48, 0.12);
    color: #FF3B30; border: none; border-radius: 8px; font-size: 11px;
    font-weight: 600; cursor: pointer; transition: all 0.2s;
  }
  .action-btn:hover { background-color: rgba(255, 59, 48, 0.22); }
  .action-btn.danger { background-color: rgba(100, 100, 100, 0.12); color: var(--text-secondary); }
  .action-btn.danger:hover { background-color: rgba(100, 100, 100, 0.22); }
  .action-btn .material-symbols-rounded { font-size: 14px; }

  .pop-btn { flex: 0 0 32px; background-color: var(--bg-panel1); color: var(--text-secondary); }
  .pop-btn:hover { background-color: var(--bg-panel-hover); color: var(--text-primary); }

  /* Settings Panel */
  .settings-panel { display: flex; flex-direction: column; gap: 10px; }
  .settings-header { display: flex; justify-content: space-between; align-items: center; }
  .settings-header h4 { font-size: 14px; font-weight: 600; color: var(--text-primary); margin: 0; }
  .close-btn {
    display: grid; place-items: center; width: 24px; height: 24px; border-radius: 6px;
    background: transparent; border: none; color: var(--text-caption); cursor: pointer;
  }
  .close-btn:hover { background-color: var(--bg-panel1); color: var(--text-primary); }
  .close-btn .material-symbols-rounded { font-size: 16px; }

  .filter-label { font-size: 11px; font-weight: 600; color: var(--text-secondary); text-transform: uppercase; letter-spacing: 0.03em; }
  .filter-input {
    width: 100%; padding: 8px 10px; font-size: 13px; font-weight: 500;
    background-color: var(--bg-panel1); border: 1px solid var(--border-subtle);
    border-radius: 8px; color: var(--text-primary); outline: none; transition: border-color 0.2s;
    box-sizing: border-box;
  }
  .filter-input:focus { border-color: #FF3B30; }
  .filter-input::placeholder { color: var(--text-caption); }

  .hint { font-size: 11px; color: var(--text-caption); margin: 0; }

  .save-btn {
    display: flex; align-items: center; justify-content: center; gap: 4px;
    padding: 8px 0; background-color: #FF3B30; color: white;
    border: none; border-radius: 8px; font-size: 12px; font-weight: 600;
    cursor: pointer; transition: all 0.2s;
  }
  .save-btn:hover { background-color: #e02020; }
  .save-btn .material-symbols-rounded { font-size: 14px; }
</style>
