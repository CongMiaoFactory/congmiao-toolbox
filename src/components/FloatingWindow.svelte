<script lang="ts">
  let { windowId, toolId, title, x, y, width, height, zIndex, onClose, onFocus, children } = $props<{
    windowId: string;
    toolId: string;
    title: string;
    x: number;
    y: number;
    width: number;
    height: number;
    zIndex: number;
    onClose: () => void;
    onFocus: () => void;
    children?: import('svelte').Snippet;
  }>();

  let isDragging = $state(false);
  let isMaximized = $state(false);
  
  // 保存最大化前的位置和大小
  let savedState = $state({ x: 0, y: 0, w: 0, h: 0 });

  let startX = $state(0);
  let startY = $state(0);
  let currentX = $state(0);
  let currentY = $state(0);
  let currentW = $state(0);
  let currentH = $state(0);

  import { onDestroy, onMount } from 'svelte';
  onMount(() => {
    currentX = x;
    currentY = y;
    currentW = width;
    currentH = height;
  });

  onDestroy(() => {
    window.removeEventListener('pointermove', handlePointerMove);
    window.removeEventListener('pointerup', handlePointerUp);
  });

  function handlePointerDown(e: PointerEvent) {
    if (isMaximized) return; // 全屏时禁止拖拽
    if (e.target instanceof HTMLElement && e.target.closest('.window-controls')) return;
    
    isDragging = true;
    startX = e.clientX - currentX;
    startY = e.clientY - currentY;
    onFocus();
    
    window.addEventListener('pointermove', handlePointerMove);
    window.addEventListener('pointerup', handlePointerUp);
  }

  function handlePointerMove(e: PointerEvent) {
    if (!isDragging) return;
    currentX = e.clientX - startX;
    currentY = e.clientY - startY;
  }

  function handlePointerUp() {
    isDragging = false;
    window.removeEventListener('pointermove', handlePointerMove);
    window.removeEventListener('pointerup', handlePointerUp);
  }

  function toggleMaximize() {
    if (isMaximized) {
      // 还原
      isMaximized = false;
      currentX = savedState.x;
      currentY = savedState.y;
      currentW = savedState.w;
      currentH = savedState.h;
    } else {
      // 最大化
      savedState = { x: currentX, y: currentY, w: currentW, h: currentH };
      isMaximized = true;
      currentX = 0;
      currentY = 0;
      currentW = window.innerWidth;
      currentH = window.innerHeight - 80; // 减去底部 Dock 栏的高度
    }
  }
</script>

<div 
  class="floating-window" 
  class:maximized={isMaximized}
  class:dragging={isDragging}
  style="transform: translate({currentX}px, {currentY}px); width: {currentW}px; height: {currentH}px; z-index: {zIndex};"
  onpointerdown={onFocus}
  role="dialog"
  aria-label={title}
  tabindex="-1"
>
  <div class="window-header" onpointerdown={handlePointerDown} ondblclick={toggleMaximize} role="presentation">
    <div class="window-controls">
      <button class="mac-btn close" onclick={onClose} aria-label="关闭窗口"></button>
      <button class="mac-btn minimize" onclick={toggleMaximize} aria-label="最小化窗口"></button>
      <button class="mac-btn maximize" onclick={toggleMaximize} aria-label="最大化窗口"></button>
    </div>
    <div class="window-title">{title}</div>
    <div class="window-spacer"></div>
  </div>
  <div class="window-content">
    {#if children}
      {@render children()}
    {/if}
  </div>
</div>

<style>
  .floating-window {
    position: absolute;
    top: 0;
    left: 0;
    background-color: var(--bg-app, #ffffff);
    border: 1px solid var(--border-subtle, rgba(0,0,0,0.1));
    border-radius: var(--radius-xl, 16px);
    box-shadow: 0 20px 40px -10px rgba(0,0,0,0.2), 0 0 0 1px rgba(0,0,0,0.05);
    display: flex;
    flex-direction: column;
    overflow: hidden;
    will-change: transform, width, height;
    transition: width 0.3s cubic-bezier(0.16, 1, 0.3, 1), height 0.3s cubic-bezier(0.16, 1, 0.3, 1);
  }

  .floating-window.dragging {
    transition: none; /* 拖拽时取消动画，防止卡顿 */
    opacity: 0.95;
  }

  .floating-window.maximized {
    border-radius: 0;
    border: none;
    box-shadow: none;
    transition: all 0.3s cubic-bezier(0.16, 1, 0.3, 1);
  }

  :global([data-theme="dark"]) .floating-window {
    background-color: var(--bg-app, #1a1a1a);
    border-color: var(--border-subtle, rgba(255,255,255,0.1));
    box-shadow: 0 20px 40px -10px rgba(0,0,0,0.5), 0 0 0 1px rgba(255,255,255,0.05);
  }

  .window-header {
    height: 48px;
    background: rgba(245, 245, 245, 0.8);
    backdrop-filter: blur(20px);
    -webkit-backdrop-filter: blur(20px);
    display: grid;
    grid-template-columns: 1fr auto 1fr;
    align-items: center;
    padding: 0 16px;
    user-select: none;
    border-bottom: 1px solid rgba(0,0,0,0.05);
  }

  .floating-window:not(.maximized) .window-header {
    cursor: grab;
  }
  
  .floating-window:not(.maximized) .window-header:active {
    cursor: grabbing;
  }

  :global([data-theme="dark"]) .window-header {
    background: rgba(40, 40, 40, 0.8);
    border-bottom-color: rgba(255,255,255,0.05);
  }

  .window-controls {
    display: flex;
    gap: 8px;
    align-items: center;
  }

  .mac-btn {
    width: 12px;
    height: 12px;
    border-radius: 50%;
    border: 1px solid rgba(0,0,0,0.1);
    cursor: pointer;
    padding: 0;
    position: relative;
    display: flex;
    align-items: center;
    justify-content: center;
  }

  :global([data-theme="dark"]) .mac-btn {
    border-color: rgba(255,255,255,0.1);
  }

  .mac-btn.close { background-color: #FF5F56; }
  .mac-btn.minimize { background-color: #FFBD2E; }
  .mac-btn.maximize { background-color: #27C93F; }

  /* 悬浮时内部显示小图标效果可以后续补充，目前保持纯净 */
  
  .window-title {
    font-size: 13px;
    font-weight: 600;
    color: var(--text-primary, #333);
    text-align: center;
    pointer-events: none;
  }

  :global([data-theme="dark"]) .window-title {
    color: var(--text-primary, #eee);
  }

  .window-content {
    flex: 1;
    overflow: auto;
    position: relative;
    display: flex;
    flex-direction: column;
    background-color: var(--bg-app);
  }

  /* --- 全局覆盖：隐藏工具内置的返回按钮和冗余大标题 --- */
  :global(.floating-window .back-btn) {
    display: none !important;
  }

  :global(.floating-window .header-left) {
    display: none !important;
  }

  :global(.floating-window .header) {
    margin-bottom: 0 !important;
    justify-content: flex-start !important;
  }

  /* 移除内置的宽度限制和过大的间距，让工具填满窗口 */
  :global(.floating-window > .window-content > div) {
    padding: 16px !important;
    max-width: 100% !important;
    height: 100% !important;
    box-sizing: border-box !important;
    gap: 16px !important;
  }
</style>
