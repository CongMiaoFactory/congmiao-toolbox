<script lang="ts">
  import { appState, settingsGroups } from '../state.svelte';
  import { encodeWallpaper } from '../persistence';
  
  let tempBgUrl = $state(appState.bgImageUrl);
  let tempBgBlur = $state(appState.bgBlur);
  let fileInput: HTMLInputElement;
  let wallpaperMessage = $state('');

  function saveBg() {
    appState.setAppearance({ bgImageUrl: tempBgUrl, bgBlur: tempBgBlur });
    wallpaperMessage = '外观设置已保存';
  }

  async function handleFileSelect(event: Event) {
    const target = event.target as HTMLInputElement;
    if (target.files && target.files.length > 0) {
      try {
        wallpaperMessage = '正在处理图片…';
        tempBgUrl = await encodeWallpaper(target.files[0]);
        appState.setAppearance({ bgImageUrl: tempBgUrl });
        wallpaperMessage = '本地壁纸已保存';
      } catch (error) {
        wallpaperMessage = error instanceof Error ? error.message : '壁纸处理失败';
      } finally {
        target.value = '';
      }
    }
  }
</script>

<div class="modal-backdrop" onclick={() => appState.settingsOpen = false} role="presentation">
  <div class="modal-content" onclick={(e) => e.stopPropagation()} onkeydown={(e) => e.stopPropagation()} role="dialog" aria-modal="true" tabindex="-1" aria-label="系统设置">
    <div class="modal-header">
      <h2>系统设置</h2>
      <button class="close-btn" onclick={() => appState.settingsOpen = false} aria-label="关闭设置">
        <span class="material-symbols-rounded">close</span>
      </button>
    </div>

    <div class="modal-body">
      <section class="settings-section">
        <h3>外观</h3>
        
        <div class="setting-item">
          <div class="setting-info">
            <span class="setting-title">主题模式</span>
            <span class="setting-desc">切换亮色或暗色模式</span>
          </div>
          {#if wallpaperMessage}<span class="wallpaper-message">{wallpaperMessage}</span>{/if}
          <button class="action-btn" onclick={() => appState.toggleTheme()}>
            <span class="material-symbols-rounded">{appState.theme === 'dark' ? 'light_mode' : 'dark_mode'}</span>
            {appState.theme === 'dark' ? '切换为亮色' : '切换为暗色'}
          </button>
        </div>

        <div class="setting-item col">
          <div class="setting-info">
            <span class="setting-title">桌面壁纸</span>
            <span class="setting-desc">输入图片 URL 或选择本地图片</span>
          </div>
          <div class="input-group">
            <input type="text" bind:value={tempBgUrl} placeholder="https://..." class="bg-input" />
            <button class="action-btn primary" onclick={saveBg}>应用</button>
            <button class="action-btn outline" onclick={() => fileInput.click()}>
              <span class="material-symbols-rounded">image</span> 本地图片
            </button>
            <input 
              type="file" 
              accept="image/*" 
              bind:this={fileInput} 
              onchange={handleFileSelect} 
              style="display: none" 
            />
          </div>
        </div>

        <div class="setting-item col">
          <div class="setting-info">
            <span class="setting-title">壁纸模糊度</span>
            <span class="setting-desc">调整桌面背景的毛玻璃模糊程度</span>
          </div>
          <div class="input-group slider-group">
            <input type="range" min="0" max="100" bind:value={tempBgBlur} oninput={saveBg} />
            <span class="blur-value">{tempBgBlur}px</span>
          </div>
        </div>
      </section>

      <section class="settings-section">
        <h3>关于系统</h3>
        <div class="about-grid">
          {#each settingsGroups as group}
            <div class="about-card">
              <h4>{group.title}</h4>
              <ul>
                {#each group.items as item}
                  <li>{item}</li>
                {/each}
              </ul>
            </div>
          {/each}
        </div>
      </section>
    </div>
  </div>
</div>

<style>
  .modal-backdrop {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.4);
    backdrop-filter: blur(4px);
    z-index: 1000;
    display: flex;
    align-items: center;
    justify-content: center;
    animation: fadeIn 0.2s ease-out;
  }

  .modal-content {
    background: var(--bg-app, #fff);
    border-radius: var(--radius-xl, 16px);
    width: 100%;
    max-width: 600px;
    max-height: 85vh;
    display: flex;
    flex-direction: column;
    box-shadow: 0 20px 40px rgba(0,0,0,0.2);
    border: 1px solid var(--border-subtle, rgba(0,0,0,0.1));
    animation: slideUp 0.3s cubic-bezier(0.16, 1, 0.3, 1);
  }

  :global([data-theme="dark"]) .modal-content {
    background: var(--bg-app, #1a1a1a);
    border-color: rgba(255,255,255,0.1);
  }

  @keyframes fadeIn {
    from { opacity: 0; }
    to { opacity: 1; }
  }

  @keyframes slideUp {
    from { opacity: 0; transform: translateY(20px) scale(0.98); }
    to { opacity: 1; transform: translateY(0) scale(1); }
  }

  .modal-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 20px 24px;
    border-bottom: 1px solid var(--border-subtle, rgba(0,0,0,0.1));
  }

  .modal-header h2 {
    margin: 0;
    font-size: 20px;
    font-weight: 600;
    color: var(--text-primary, #333);
  }

  :global([data-theme="dark"]) .modal-header h2 { color: #eee; }
  :global([data-theme="dark"]) .modal-header { border-bottom-color: rgba(255,255,255,0.1); }

  .close-btn {
    background: transparent;
    border: none;
    cursor: pointer;
    width: 32px;
    height: 32px;
    border-radius: 8px;
    display: flex;
    align-items: center;
    justify-content: center;
    color: var(--text-secondary, #666);
    transition: all 0.2s;
  }

  .close-btn:hover {
    background: var(--bg-panel-hover, rgba(0,0,0,0.05));
    color: var(--text-primary, #333);
  }

  :global([data-theme="dark"]) .close-btn:hover { color: #eee; background: rgba(255,255,255,0.1); }

  .modal-body {
    padding: 24px;
    overflow-y: auto;
    display: flex;
    flex-direction: column;
    gap: 32px;
  }

  .settings-section {
    display: flex;
    flex-direction: column;
    gap: 16px;
  }

  .settings-section h3 {
    margin: 0;
    font-size: 14px;
    font-weight: 600;
    color: var(--text-secondary, #666);
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }

  :global([data-theme="dark"]) .settings-section h3 { color: #aaa; }

  .setting-item {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 16px;
    background: var(--bg-panel0, rgba(0,0,0,0.02));
    border-radius: 12px;
    border: 1px solid var(--border-subtle, rgba(0,0,0,0.05));
  }

  .setting-item.col {
    flex-direction: column;
    align-items: flex-start;
    gap: 12px;
  }

  :global([data-theme="dark"]) .setting-item {
    background: var(--bg-panel0, rgba(255,255,255,0.02));
    border-color: rgba(255,255,255,0.05);
  }

  .setting-info {
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .setting-title {
    font-size: 15px;
    font-weight: 600;
    color: var(--text-primary, #333);
  }

  .setting-desc {
    font-size: 13px;
    color: var(--text-secondary, #666);
  }

  .wallpaper-message {
    color: var(--text-secondary, #666);
    font-size: 12px;
  }

  :global([data-theme="dark"]) .setting-title { color: #eee; }
  :global([data-theme="dark"]) .setting-desc { color: #aaa; }

  .action-btn {
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 8px 16px;
    border-radius: 8px;
    background: var(--bg-app, #fff);
    border: 1px solid var(--border-subtle, #ccc);
    color: var(--text-primary, #333);
    font-size: 13px;
    font-weight: 600;
    cursor: pointer;
    transition: all 0.2s;
  }

  .action-btn:hover {
    background: var(--bg-panel-hover, #f5f5f5);
  }

  .action-btn.primary {
    background: #0A84FF;
    color: white;
    border: none;
  }

  .action-btn.primary:hover {
    background: #0070e6;
  }

  .action-btn.outline {
    background: transparent;
    border: 1px solid var(--border-subtle, #ccc);
    color: var(--text-primary, #333);
  }

  .action-btn.outline:hover {
    background: var(--bg-panel-hover, #f5f5f5);
  }

  :global([data-theme="dark"]) .action-btn:not(.primary) {
    background: #2a2a2a;
    border-color: #444;
    color: #eee;
  }
  :global([data-theme="dark"]) .action-btn:not(.primary):hover { background: #333; }

  .input-group {
    display: flex;
    gap: 8px;
    width: 100%;
  }

  .slider-group {
    display: flex;
    align-items: center;
    gap: 16px;
    width: 100%;
  }

  .slider-group input[type="range"] {
    flex: 1;
  }

  .blur-value {
    font-size: 13px;
    font-weight: 600;
    color: var(--text-secondary, #666);
    min-width: 40px;
    text-align: right;
  }

  :global([data-theme="dark"]) .blur-value { color: #aaa; }

  .bg-input {
    flex: 1;
    padding: 8px 12px;
    border-radius: 8px;
    border: 1px solid var(--border-subtle, #ccc);
    background: var(--bg-app, #fff);
    color: var(--text-primary, #333);
    font-size: 14px;
    outline: none;
  }

  .bg-input:focus {
    border-color: #0A84FF;
  }

  :global([data-theme="dark"]) .bg-input {
    background: #1a1a1a;
    border-color: #444;
    color: #eee;
  }

  .about-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
    gap: 16px;
  }

  .about-card {
    background: var(--bg-panel0, rgba(0,0,0,0.02));
    border-radius: 12px;
    padding: 16px;
    border: 1px solid var(--border-subtle, rgba(0,0,0,0.05));
  }

  :global([data-theme="dark"]) .about-card {
    background: rgba(255,255,255,0.02);
    border-color: rgba(255,255,255,0.05);
  }

  .about-card h4 {
    margin: 0 0 12px 0;
    font-size: 13px;
    color: var(--text-primary, #333);
  }

  :global([data-theme="dark"]) .about-card h4 { color: #eee; }

  .about-card ul {
    margin: 0;
    padding: 0;
    list-style: none;
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .about-card li {
    font-size: 12px;
    color: var(--text-secondary, #666);
  }

  :global([data-theme="dark"]) .about-card li { color: #aaa; }
</style>
