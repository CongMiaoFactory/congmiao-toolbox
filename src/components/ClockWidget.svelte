<script lang="ts">
  import { onMount } from 'svelte';

  let time = $state(new Date());

  onMount(() => {
    const interval = setInterval(() => {
      time = new Date();
    }, 1000);
    return () => clearInterval(interval);
  });

  let hours = $derived(time.getHours().toString().padStart(2, '0'));
  let minutes = $derived(time.getMinutes().toString().padStart(2, '0'));
  let seconds = $derived(time.getSeconds().toString().padStart(2, '0'));
  let dateStr = $derived(time.toLocaleDateString('zh-CN', { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' }));
</script>

<div class="clock-widget">
  <div class="time">
    <span class="hours">{hours}</span>
    <span class="colon">:</span>
    <span class="minutes">{minutes}</span>
    <span class="seconds">{seconds}</span>
  </div>
  <div class="date">{dateStr}</div>
</div>

<style>
  .clock-widget {
    background-color: var(--bg-panel0, rgba(255, 255, 255, 0.8));
    backdrop-filter: blur(10px);
    border: 1px solid var(--border-subtle, rgba(0, 0, 0, 0.1));
    border-radius: var(--radius-xl, 20px);
    padding: 24px;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    box-shadow: var(--shadow-md, 0 4px 6px rgba(0,0,0,0.1));
    color: var(--text-primary, #333);
  }

  :global([data-theme="dark"]) .clock-widget {
    background-color: var(--bg-panel0, rgba(30, 30, 30, 0.8));
    border-color: var(--border-subtle, rgba(255, 255, 255, 0.1));
    color: var(--text-primary, #fff);
  }

  .time {
    font-size: 48px;
    font-weight: 700;
    font-variant-numeric: tabular-nums;
    display: flex;
    align-items: baseline;
    gap: 4px;
    font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
  }

  .seconds {
    font-size: 24px;
    color: var(--text-secondary, #666);
    margin-left: 4px;
  }

  :global([data-theme="dark"]) .seconds {
    color: var(--text-secondary, #aaa);
  }

  .date {
    font-size: 14px;
    color: var(--text-secondary, #666);
    margin-top: 8px;
  }

  :global([data-theme="dark"]) .date {
    color: var(--text-secondary, #aaa);
  }
</style>
