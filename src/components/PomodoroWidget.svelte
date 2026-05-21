<script lang="ts">
  import { onMount } from 'svelte';

  const WORK_TIME = 25 * 60;
  const BREAK_TIME = 5 * 60;

  let timeLeft = $state(WORK_TIME);
  let isRunning = $state(false);
  let isWork = $state(true);
  let intervalId: number | null = null;

  function toggleTimer() {
    if (isRunning) {
      if (intervalId) clearInterval(intervalId);
      isRunning = false;
    } else {
      isRunning = true;
      intervalId = window.setInterval(() => {
        if (timeLeft > 0) {
          timeLeft--;
        } else {
          // Switch mode
          isWork = !isWork;
          timeLeft = isWork ? WORK_TIME : BREAK_TIME;
          // Could play a sound here
        }
      }, 1000);
    }
  }

  function resetTimer() {
    if (intervalId) clearInterval(intervalId);
    isRunning = false;
    timeLeft = isWork ? WORK_TIME : BREAK_TIME;
  }

  function switchMode(mode: 'work' | 'break') {
    isWork = mode === 'work';
    resetTimer();
  }

  let minutes = $derived(Math.floor(timeLeft / 60).toString().padStart(2, '0'));
  let seconds = $derived((timeLeft % 60).toString().padStart(2, '0'));
  let progress = $derived(100 - (timeLeft / (isWork ? WORK_TIME : BREAK_TIME)) * 100);
</script>

<div class="pomodoro-widget" class:break-mode={!isWork}>
  <div class="header">
    <button class:active={isWork} onclick={() => switchMode('work')}>专注</button>
    <button class:active={!isWork} onclick={() => switchMode('break')}>休息</button>
  </div>

  <div class="timer-display">
    <svg class="progress-ring" viewBox="0 0 100 100">
      <circle class="bg" cx="50" cy="50" r="45"></circle>
      <circle class="progress" cx="50" cy="50" r="45" style="stroke-dasharray: 283; stroke-dashoffset: {283 - (progress / 100) * 283};"></circle>
    </svg>
    <div class="time-text">
      {minutes}:{seconds}
    </div>
  </div>

  <div class="controls">
    <button class="play-btn" onclick={toggleTimer}>
      <span class="material-symbols-rounded">{isRunning ? 'pause' : 'play_arrow'}</span>
    </button>
    <button class="reset-btn" onclick={resetTimer}>
      <span class="material-symbols-rounded">replay</span>
    </button>
  </div>
</div>

<style>
  .pomodoro-widget {
    background-color: var(--bg-panel0, rgba(255, 255, 255, 0.8));
    backdrop-filter: blur(10px);
    border: 1px solid var(--border-subtle, rgba(0, 0, 0, 0.1));
    border-radius: var(--radius-xl, 20px);
    padding: 24px;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 20px;
    box-shadow: var(--shadow-md, 0 4px 6px rgba(0,0,0,0.1));
    --theme-color: #FF3B30;
  }

  :global([data-theme="dark"]) .pomodoro-widget {
    background-color: var(--bg-panel0, rgba(30, 30, 30, 0.8));
    border-color: var(--border-subtle, rgba(255, 255, 255, 0.1));
  }

  .pomodoro-widget.break-mode {
    --theme-color: #34C759;
  }

  .header {
    display: flex;
    background: var(--bg-element, rgba(0,0,0,0.05));
    border-radius: 12px;
    padding: 4px;
    gap: 4px;
  }

  :global([data-theme="dark"]) .header {
    background: var(--bg-element, rgba(255,255,255,0.1));
  }

  .header button {
    background: transparent;
    border: none;
    padding: 6px 16px;
    border-radius: 8px;
    font-size: 14px;
    color: var(--text-secondary, #666);
    cursor: pointer;
    transition: all 0.2s;
  }

  :global([data-theme="dark"]) .header button {
    color: var(--text-secondary, #aaa);
  }

  .header button.active {
    background: var(--theme-color);
    color: white;
    box-shadow: 0 2px 4px rgba(0,0,0,0.1);
  }

  .timer-display {
    position: relative;
    width: 160px;
    height: 160px;
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .progress-ring {
    position: absolute;
    top: 0;
    left: 0;
    width: 100%;
    height: 100%;
    transform: rotate(-90deg);
  }

  .progress-ring circle {
    fill: none;
    stroke-width: 6;
    stroke-linecap: round;
  }

  .progress-ring .bg {
    stroke: var(--bg-element, rgba(0,0,0,0.05));
  }

  :global([data-theme="dark"]) .progress-ring .bg {
    stroke: var(--bg-element, rgba(255,255,255,0.1));
  }

  .progress-ring .progress {
    stroke: var(--theme-color);
    transition: stroke-dashoffset 1s linear;
  }

  .time-text {
    font-size: 36px;
    font-weight: 700;
    font-variant-numeric: tabular-nums;
    color: var(--text-primary, #333);
    font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
  }

  :global([data-theme="dark"]) .time-text {
    color: var(--text-primary, #eee);
  }

  .controls {
    display: flex;
    gap: 16px;
  }

  .controls button {
    width: 48px;
    height: 48px;
    border-radius: 50%;
    border: none;
    display: flex;
    align-items: center;
    justify-content: center;
    cursor: pointer;
    transition: all 0.2s;
  }

  .play-btn {
    background: var(--theme-color);
    color: white;
    box-shadow: 0 4px 8px rgba(0,0,0,0.15);
  }

  .play-btn:hover {
    transform: scale(1.05);
  }

  .reset-btn {
    background: var(--bg-element, #eee);
    color: var(--text-secondary, #666);
  }

  :global([data-theme="dark"]) .reset-btn {
    background: var(--bg-element, #333);
    color: var(--text-secondary, #ccc);
  }

  .reset-btn:hover {
    background: var(--bg-panel-hover, #ddd);
  }

  :global([data-theme="dark"]) .reset-btn:hover {
    background: var(--bg-panel-hover, #444);
  }
</style>
