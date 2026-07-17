<script lang="ts">
  import type { Component } from 'svelte';
  import type { WindowToolId } from '../toolRegistry';
  import { loadWindowComponent } from '../windowComponents';

  let { toolId }: { toolId: WindowToolId } = $props();
  let ToolComponent = $state<Component | null>(null);
  let loadError = $state('');

  $effect(() => {
    const requestedTool = toolId;
    let active = true;
    ToolComponent = null;
    loadError = '';
    void loadWindowComponent(requestedTool)
      .then((module) => {
        if (active && requestedTool === toolId) ToolComponent = module.default;
      })
      .catch((error) => {
        console.error(`Failed to load tool ${requestedTool}`, error);
        if (active && requestedTool === toolId) loadError = '工具加载失败，请关闭窗口后重试';
      });
    return () => { active = false; };
  });
</script>

{#if ToolComponent}
  <ToolComponent />
{:else if loadError}
  <div class="tool-load-state error"><span class="material-symbols-rounded">error</span>{loadError}</div>
{:else}
  <div class="tool-load-state"><span class="material-symbols-rounded loading">progress_activity</span>正在加载工具…</div>
{/if}

<style>
  .tool-load-state{height:100%;min-height:180px;display:flex;align-items:center;justify-content:center;gap:9px;color:var(--text-secondary)}
  .tool-load-state.error{color:#e74c3c}.loading{animation:spin 1s linear infinite}@keyframes spin{to{transform:rotate(360deg)}}
</style>
