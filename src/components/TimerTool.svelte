<script lang="ts">
  import { appState } from '../state.svelte';

  let mode = $state<'stopwatch' | 'countdown'>('stopwatch');

  // ---------- STOPWATCH ----------
  let swTime = $state(0);
  let swRunning = $state(false);
  let swInterval: number;
  let swLaps = $state<number[]>([]);

  $effect(() => {
    return () => { if (swInterval) clearInterval(swInterval); };
  });

  const formatSw = (ms: number) => {
    const min = Math.floor(ms / 60000).toString().padStart(2, '0');
    const sec = Math.floor((ms % 60000) / 1000).toString().padStart(2, '0');
    const mil = Math.floor((ms % 1000) / 10).toString().padStart(2, '0');
    return { min, sec, mil };
  };

  const toggleSw = () => {
    if (swRunning) {
      clearInterval(swInterval);
      swRunning = false;
    } else {
      const start = Date.now() - swTime;
      swInterval = window.setInterval(() => {
        swTime = Date.now() - start;
      }, 10);
      swRunning = true;
    }
  };

  const resetSw = () => {
    clearInterval(swInterval);
    swRunning = false;
    swTime = 0;
    swLaps = [];
  };

  const lapSw = () => {
    swLaps = [swTime, ...swLaps];
  };

  const swFormatted = $derived(formatSw(swTime));

  // ---------- COUNTDOWN ----------
  let cdInputMins = $state(5);
  let cdTime = $state(5 * 60000);
  let cdTotal = $state(5 * 60000);
  let cdRunning = $state(false);
  let cdInterval: number;

  $effect(() => {
    return () => { if (cdInterval) clearInterval(cdInterval); };
  });

  const toggleCd = () => {
    if (cdRunning) {
      clearInterval(cdInterval);
      cdRunning = false;
    } else {
      if (cdTime <= 0) {
        cdTime = cdInputMins * 60000;
        cdTotal = cdTime;
      }
      const target = Date.now() + cdTime;
      cdInterval = window.setInterval(() => {
        cdTime = target - Date.now();
        if (cdTime <= 0) {
          cdTime = 0;
          clearInterval(cdInterval);
          cdRunning = false;
        }
      }, 50);
      cdRunning = true;
    }
  };

  const resetCd = () => {
    clearInterval(cdInterval);
    cdRunning = false;
    cdTime = cdInputMins * 60000;
    cdTotal = cdTime;
  };

  const setCdPreset = (mins: number) => {
    cdInputMins = mins;
    resetCd();
  };

  const formatCd = (ms: number) => {
    const min = Math.floor(ms / 60000).toString().padStart(2, '0');
    const sec = Math.floor((ms % 60000) / 1000).toString().padStart(2, '0');
    return `${min}:${sec}`;
  };

  const cdPercent = $derived(cdTotal > 0 ? (cdTime / cdTotal) * 100 : 0);
</script>

<div class="tool-view">
  <button class="back-btn" onclick={() => appState.activeToolId = null}>
    <span class="material-symbols-rounded">arrow_back</span>
    <span>全部功能</span>
  </button>

  <div class="header">
    <div class="header-left">
      <div class="icon red">
        <span class="material-symbols-rounded">timer</span>
      </div>
      <div>
        <p class="eyebrow">生产力工具</p>
        <h3>计时器与秒表</h3>
      </div>
    </div>

    <div class="mode-toggle">
      <button 
        class="toggle-btn {mode === 'stopwatch' ? 'active' : ''}" 
        onclick={() => mode = 'stopwatch'}
      >
        <span class="material-symbols-rounded">timer</span>秒表
      </button>
      <button 
        class="toggle-btn {mode === 'countdown' ? 'active' : ''}" 
        onclick={() => mode = 'countdown'}
      >
        <span class="material-symbols-rounded">hourglass_empty</span>倒计时
      </button>
    </div>
  </div>

  <div class="content-area">
    {#if mode === 'stopwatch'}
      <div class="clock-display">
        <div class="digits">
          <span class="big">{swFormatted.min}:{swFormatted.sec}</span>
          <span class="small">.{swFormatted.mil}</span>
        </div>
        
        <div class="controls">
          <button class="btn reset" onclick={resetSw} disabled={swTime === 0 && !swRunning}>
            <span class="material-symbols-rounded">restart_alt</span>重置
          </button>
          
          {#if swRunning}
            <button class="btn pause" onclick={toggleSw}>
              <span class="material-symbols-rounded">pause</span>暂停
            </button>
            <button class="btn lap" onclick={lapSw}>
              <span class="material-symbols-rounded">flag</span>计圈
            </button>
          {:else}
            <button class="btn start" onclick={toggleSw}>
              <span class="material-symbols-rounded">play_arrow</span>开始
            </button>
          {/if}
        </div>
      </div>

      {#if swLaps.length > 0}
        <div class="laps-list">
          {#each swLaps as lap, i}
            <div class="lap-item">
              <span class="lap-num">圈次 {swLaps.length - i}</span>
              <span class="lap-time">
                {formatSw(lap).min}:{formatSw(lap).sec}.{formatSw(lap).mil}
              </span>
            </div>
          {/each}
        </div>
      {/if}

    {:else}
      <div class="clock-display">
        <div class="countdown-circle">
          <svg viewBox="0 0 100 100" class="progress-ring">
             <circle cx="50" cy="50" r="45" class="bg"></circle>
             <circle cx="50" cy="50" r="45" class="fill" 
                     stroke-dasharray="283" 
                     stroke-dashoffset={283 - (283 * cdPercent / 100)}></circle>
          </svg>
          <div class="cd-digits" class:blink={cdTime === 0}>
             {formatCd(cdTime)}
          </div>
        </div>
        
        <div class="presets">
          <button class="preset-btn" onclick={() => setCdPreset(1)}>1分钟</button>
          <button class="preset-btn" onclick={() => setCdPreset(5)}>5分钟</button>
          <button class="preset-btn" onclick={() => setCdPreset(15)}>15分钟</button>
          <button class="preset-btn" onclick={() => setCdPreset(25)}>番茄钟(25分)</button>
        </div>

        <div class="controls">
          <button class="btn reset" onclick={resetCd} disabled={cdTime === cdTotal && !cdRunning}>
            <span class="material-symbols-rounded">stop</span>重置
          </button>
          
          {#if cdRunning}
            <button class="btn pause" onclick={toggleCd}>
              <span class="material-symbols-rounded">pause</span>暂停
            </button>
          {:else}
            <button class="btn start" onclick={toggleCd}>
              <span class="material-symbols-rounded">play_arrow</span>开始
            </button>
          {/if}
        </div>
      </div>
    {/if}
  </div>
</div>

<style>
  .tool-view {
    display: flex;
    flex-direction: column;
    gap: 24px;
    height: 100%;
    max-width: 800px;
    margin: 0 auto;
    width: 100%;
  }

  .back-btn {
    display: flex;
    align-items: center;
    gap: 8px;
    width: fit-content;
    color: var(--text-secondary);
    font-size: 13px;
    font-weight: 600;
    transition: color var(--transition-fast);
  }
  .back-btn:hover { color: var(--text-primary); }
  .back-btn .material-symbols-rounded { font-size: 18px; }

  .header {
    display: flex;
    justify-content: space-between;
    align-items: flex-end;
  }

  .header-left {
    display: flex;
    align-items: center;
    gap: 16px;
  }

  .icon {
    display: grid;
    place-items: center;
    width: 48px;
    height: 48px;
    border-radius: 14px;
    background-color: var(--bg-app);
    border: 1px solid var(--border-subtle);
  }

  .icon.red {
    color: #FF3B30;
    background-color: rgba(255, 59, 48, 0.15);
    border-color: rgba(255, 59, 48, 0.2);
  }

  .eyebrow {
    font-size: 11px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.1em;
    color: var(--text-caption);
    margin-bottom: 4px;
  }

  h3 {
    font-size: 24px;
    font-weight: 600;
    color: var(--text-primary);
    letter-spacing: -0.02em;
  }

  .mode-toggle {
    display: flex;
    background-color: var(--bg-panel0);
    padding: 4px;
    border-radius: 8px;
    border: 1px solid var(--border-subtle);
  }

  .toggle-btn {
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 8px 16px;
    font-size: 13px;
    font-weight: 600;
    border-radius: 6px;
    color: var(--text-secondary);
    transition: all var(--transition-fast);
  }
  .toggle-btn .material-symbols-rounded { font-size: 16px; }

  .toggle-btn.active {
    background-color: var(--bg-app);
    color: var(--text-primary);
    box-shadow: var(--shadow-sm);
  }

  .content-area {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    flex: 1;
    background-color: var(--bg-panel0);
    border: 1px solid var(--border-subtle);
    border-radius: var(--radius-lg);
    box-shadow: var(--shadow-sm);
    padding: 40px;
    overflow: hidden;
  }

  .clock-display {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 32px;
  }

  .digits {
    font-family: ui-monospace, SFMono-Regular, monospace;
    font-variant-numeric: tabular-nums;
    display: flex;
    align-items: baseline;
    color: var(--text-primary);
  }

  .digits .big {
    font-size: 84px;
    font-weight: 300;
    letter-spacing: -0.02em;
  }

  .digits .small {
    font-size: 48px;
    font-weight: 400;
    color: var(--text-secondary);
  }

  .controls {
    display: flex;
    gap: 16px;
  }

  .btn {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 14px 24px;
    font-size: 15px;
    font-weight: 600;
    border-radius: var(--radius-full);
    cursor: pointer;
    transition: all 0.2s;
    border: none;
    outline: none;
  }

  .btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .btn.start { background-color: #34C759; color: white; }
  .btn.start:not(:disabled):hover { background-color: #30D158; box-shadow: 0 4px 12px rgba(52, 199, 89, 0.3); }

  .btn.pause { background-color: #FF9500; color: white; }
  .btn.pause:not(:disabled):hover { background-color: #FF9F0A; box-shadow: 0 4px 12px rgba(255, 149, 0, 0.3); }

  .btn.reset { background-color: var(--bg-panel1); color: var(--text-primary); border: 1px solid var(--border-subtle); }
  .btn.reset:not(:disabled):hover { background-color: var(--bg-app); border-color: var(--border-focus); }

  .btn.lap { background-color: var(--bg-panel1); color: var(--text-primary); border: 1px solid var(--border-subtle); }
  .btn.lap:not(:disabled):hover { background-color: var(--bg-app); border-color: var(--border-focus); }

  /* Laps */
  .laps-list {
    margin-top: 32px;
    width: 100%;
    max-width: 400px;
    display: flex;
    flex-direction: column;
    max-height: 200px;
    overflow-y: auto;
    border-top: 1px solid var(--border-subtle);
  }

  .lap-item {
    display: flex;
    justify-content: space-between;
    padding: 12px 0;
    border-bottom: 1px solid var(--border-subtle);
    font-family: ui-monospace, SFMono-Regular, monospace;
    font-size: 14px;
    color: var(--text-primary);
  }

  .lap-num { color: var(--text-secondary); }

  /* Countdown specials */
  .countdown-circle {
    position: relative;
    width: 240px;
    height: 240px;
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .progress-ring {
    position: absolute;
    top: 0; left: 0; width: 100%; height: 100%;
    transform: rotate(-90deg);
  }

  .progress-ring circle {
    fill: transparent;
    stroke-width: 4;
  }

  .progress-ring .bg {
    stroke: var(--bg-panel1);
  }

  .progress-ring .fill {
    stroke: #FF3B30;
    transition: stroke-dashoffset 0.1s linear;
  }

  .cd-digits {
    font-family: ui-monospace, SFMono-Regular, monospace;
    font-size: 56px;
    font-weight: 300;
    color: var(--text-primary);
  }

  .cd-digits.blink {
    color: #FF3B30;
    animation: blinker 1s linear infinite;
  }

  @keyframes blinker { 50% { opacity: 0; } }

  .presets {
    display: flex;
    gap: 12px;
  }

  .preset-btn {
    background-color: var(--bg-panel1);
    color: var(--text-secondary);
    border: 1px solid var(--border-subtle);
    padding: 8px 16px;
    border-radius: var(--radius-full);
    font-size: 13px;
    font-weight: 600;
    transition: all 0.2s;
  }

  .preset-btn:hover {
    background-color: var(--bg-app);
    color: var(--text-primary);
    border-color: var(--border-focus);
  }
</style>
