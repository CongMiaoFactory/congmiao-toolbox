<script lang="ts">
  import { appState } from '../state.svelte';
  import { onDestroy } from 'svelte';

  let targetFormat = $state('image/webp');
  let targetQuality = $state(90);
  let fileObj = $state<File | null>(null);
  let imageUrl = $state('');
  let dragHover = $state(false);

  const handleDragOver = (e: DragEvent) => { e.preventDefault(); dragHover = true; };
  const handleDragLeave = (e: DragEvent) => { e.preventDefault(); dragHover = false; };

  const processFile = (file: File) => {
    if (!file || !file.type.startsWith('image/')) return;
    fileObj = file;
    if (imageUrl) URL.revokeObjectURL(imageUrl);
    imageUrl = URL.createObjectURL(file);
  };

  const handleFileDrop = (e: DragEvent) => {
    e.preventDefault();
    dragHover = false;
    const file = e.dataTransfer?.files[0];
    if (file) processFile(file);
  };

  const handleFileInput = (e: Event) => {
    const target = e.target as HTMLInputElement;
    if (target.files && target.files.length > 0) {
      processFile(target.files[0]);
    }
  };

  const handleConvert = () => {
    if (!imageUrl) return;
    const img = new Image();
    img.crossOrigin = "anonymous";
    img.onload = () => {
      const canvas = document.createElement('canvas');
      canvas.width = img.width;
      canvas.height = img.height;
      
      const ctx = canvas.getContext('2d');
      if (ctx) {
        // Fill white background for transparent images converting to JPEG
        if (targetFormat === 'image/jpeg') {
          ctx.fillStyle = '#FFFFFF';
          ctx.fillRect(0, 0, canvas.width, canvas.height);
        }
        ctx.drawImage(img, 0, 0);
      }
      
      const dataUrl = canvas.toDataURL(targetFormat, targetQuality / 100);
      const a = document.createElement('a');
      a.href = dataUrl;
      const ext = targetFormat.split('/')[1];
      const name = fileObj ? fileObj.name.split('.')[0] : 'converted';
      a.download = `${name}.${ext}`;
      a.click();
    };
    img.src = imageUrl;
  };

  onDestroy(() => {
    if (imageUrl) URL.revokeObjectURL(imageUrl);
  });
</script>

<div class="tool-view">
  <button class="back-btn" onclick={() => appState.activeToolId = null}>
    <span class="material-symbols-rounded">arrow_back</span>
    <span>全部功能</span>
  </button>

  <div class="header">
    <div class="header-left">
      <div class="icon orange">
        <span class="material-symbols-rounded">imagesmode</span>
      </div>
      <div>
        <p class="eyebrow">多媒体工具</p>
        <h3>图片格式离线转换</h3>
      </div>
    </div>
  </div>

  <div class="content-area">
    <!-- Drop Zone -->
    <div class="drop-zone" 
         role="button"
         tabindex="0"
         class:hover={dragHover}
         class:has-image={!!fileObj}
         ondragover={handleDragOver}
         ondragleave={handleDragLeave}
         ondrop={handleFileDrop}>
         
      {#if imageUrl}
        <img src={imageUrl} alt="Preview" class="preview-img" />
      {/if}

      <div class="drop-texts" class:overlay={!!fileObj}>
        <span class="material-symbols-rounded drop-icon">add_photo_alternate</span>
        <h4>一拖即转</h4>
        <p>将常见长图或照片拖拽到此处，纯离线极速处理</p>
      </div>
      <input type="file" class="file-input" accept="image/*" onchange={handleFileInput} />
    </div>

    <!-- Controls Sidebar -->
    <div class="controls-panel">
      <div class="pane-header">转换设置</div>

      <div class="control-group">
        <span class="label">目标格式 (Target Format)</span>
        <div class="radio-group">
          <label class="radio-label" class:active={targetFormat === 'image/webp'}>
            <input type="radio" bind:group={targetFormat} value="image/webp" />
            <span class="btn-text">WEBP (推荐)</span>
          </label>
          <label class="radio-label" class:active={targetFormat === 'image/png'}>
            <input type="radio" bind:group={targetFormat} value="image/png" />
            <span class="btn-text">PNG</span>
          </label>
          <label class="radio-label" class:active={targetFormat === 'image/jpeg'}>
            <input type="radio" bind:group={targetFormat} value="image/jpeg" />
            <span class="btn-text">JPEG</span>
          </label>
        </div>
      </div>

      {#if targetFormat === 'image/webp' || targetFormat === 'image/jpeg'}
      <div class="control-group">
        <div class="slider-header">
          <span class="label">清晰度 (Quality)</span>
          <span class="val">{targetQuality}%</span>
        </div>
        <input type="range" min="10" max="100" bind:value={targetQuality} class="slider" />
      </div>
      {/if}

      <div class="spacer"></div>

      <button class="convert-btn" disabled={!fileObj} onclick={handleConvert}>
        <span class="material-symbols-rounded">download</span>
        无损转换并保存
      </button>
    </div>
  </div>
</div>

<style>
  .tool-view {
    display: flex;
    flex-direction: column;
    gap: 24px;
    height: 100%;
    max-width: 1200px;
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

  .icon.orange {
    color: #FF9500;
    background-color: rgba(255, 149, 0, 0.15);
    border-color: rgba(255, 149, 0, 0.2);
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

  .content-area {
    display: flex;
    gap: 32px;
    flex: 1;
    min-height: 0;
  }

  .drop-zone {
    flex: 2;
    display: flex;
    align-items: center;
    justify-content: center;
    background-color: var(--bg-panel0);
    border: 3px dashed var(--border-focus);
    border-radius: var(--radius-lg);
    position: relative;
    cursor: pointer;
    overflow: hidden;
    transition: all 0.2s;
  }

  .drop-zone:hover, .drop-zone.hover {
    background-color: var(--bg-panel-hover);
    border-color: #FF9500;
  }

  .drop-zone.has-image {
    border: 1px solid var(--border-subtle);
    background-color: #000;
  }

  .file-input {
    position: absolute;
    top: 0; left: 0; width: 100%; height: 100%;
    opacity: 0;
    cursor: pointer;
    z-index: 10;
  }

  .preview-img {
    width: 100%;
    height: 100%;
    object-fit: contain;
    position: absolute;
    top: 0; left: 0;
  }

  .drop-texts {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 12px;
    z-index: 5;
    pointer-events: none;
  }

  .drop-texts.overlay {
    background-color: rgba(0, 0, 0, 0.6);
    padding: 24px 32px;
    border-radius: 16px;
    backdrop-filter: blur(8px);
    color: white;
    opacity: 0;
    transition: opacity 0.2s;
  }

  .drop-zone:hover .drop-texts.overlay {
    opacity: 1;
  }

  .drop-icon {
    font-size: 56px;
    color: var(--text-secondary);
  }

  .drop-texts.overlay .drop-icon {
    color: #fff;
  }

  .drop-texts h4 {
    font-size: 18px;
    font-weight: 600;
    color: inherit;
  }

  .drop-texts p {
    font-size: 14px;
    color: var(--text-caption);
  }

  .controls-panel {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 24px;
    background-color: var(--bg-panel0);
    border: 1px solid var(--border-subtle);
    border-radius: var(--radius-lg);
    padding: 24px;
    box-shadow: var(--shadow-sm);
  }

  .pane-header {
    font-size: 18px;
    font-weight: 700;
    color: var(--text-primary);
    border-bottom: 1px solid var(--border-subtle);
    padding-bottom: 12px;
  }

  .control-group {
    display: flex;
    flex-direction: column;
    gap: 12px;
  }

  .label {
    font-size: 13px;
    font-weight: 600;
    color: var(--text-secondary);
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }

  .radio-group {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .radio-label {
    display: flex;
    align-items: center;
    padding: 12px 16px;
    background-color: var(--bg-panel1);
    border: 1px solid var(--border-subtle);
    border-radius: var(--radius-md);
    cursor: pointer;
    transition: all 0.2s;
  }

  .radio-label input {
    display: none;
  }

  .radio-label.active {
    background-color: rgba(255, 149, 0, 0.1);
    border-color: #FF9500;
    color: #FF9500;
  }

  .btn-text {
    font-size: 14px;
    font-weight: 600;
  }

  .slider-header {
    display: flex;
    justify-content: space-between;
  }

  .val {
    font-size: 13px;
    font-weight: 700;
    font-family: ui-monospace, SFMono-Regular, monospace;
    color: var(--text-primary);
  }

  .slider {
    -webkit-appearance: none;
    appearance: none;
    width: 100%;
    height: 6px;
    background: var(--bg-panel1);
    border-radius: 4px;
    outline: none;
  }

  .slider::-webkit-slider-thumb {
    -webkit-appearance: none;
    width: 18px;
    height: 18px;
    border-radius: 50%;
    background: #FF9500;
    cursor: pointer;
    box-shadow: var(--shadow-sm);
  }

  .spacer {
    flex: 1;
  }

  .convert-btn {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 10px;
    width: 100%;
    padding: 16px;
    background: linear-gradient(135deg, #FF9500, #FF3B30);
    color: white;
    font-size: 16px;
    font-weight: 700;
    border-radius: var(--radius-md);
    border: none;
    cursor: pointer;
    transition: transform 0.2s, opacity 0.2s;
    box-shadow: 0 4px 12px rgba(255, 149, 0, 0.3);
  }

  .convert-btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
    background: var(--bg-panel1);
    color: var(--text-secondary);
    box-shadow: none;
  }

  .convert-btn:not(:disabled):hover {
    transform: translateY(-2px);
  }
</style>
