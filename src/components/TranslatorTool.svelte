<script lang="ts">
  import { appState } from '../state.svelte';
  
  let sourceText = $state('');
  let translatedText = $state('');
  let isTranslating = $state(false);
  let errorMsg = $state('');
  
  // Standard lang pairs supported by MyMemory API (free public)
  let sourceLang = $state('en');
  let targetLang = $state('zh-CN');
  let timer: ReturnType<typeof setTimeout>;

  const translate = async () => {
    errorMsg = '';
    if (!sourceText.trim()) { 
      translatedText = ''; 
      isTranslating = false;
      return; 
    }
    
    isTranslating = true;
    try {
      const url = `https://translate.googleapis.com/translate_a/single?client=gtx&sl=${sourceLang}&tl=${targetLang}&dt=t&q=${encodeURIComponent(sourceText)}`;
      const res = await fetch(url);
      const data = await res.json();
      
      if (data && data[0]) {
        translatedText = data[0].map((item: any) => item[0]).join('');
      } else {
        errorMsg = '翻译服务异常';
      }
    } catch (e) {
      errorMsg = '网络错误，请检查网络连接是否通畅 (可能需要代理)';
    }
    isTranslating = false;
  };
  
  const handleInput = () => {
    clearTimeout(timer);
    isTranslating = true;
    timer = setTimeout(translate, 600);
  };
  
  const swapLangs = () => {
    const tempLang = sourceLang; 
    sourceLang = targetLang; 
    targetLang = tempLang;
    
    const tempText = sourceText; 
    sourceText = translatedText; 
    translatedText = tempText;
    
    // Do not trigger fetch immediately if swapping blank
    if (sourceText) {
      translate();
    }
  };

  const handleCopy = async () => {
    if (!translatedText) return;
    try { await navigator.clipboard.writeText(translatedText); } 
    catch (e) { console.error('Copy failed'); }
  };
</script>

<div class="tool-view">
  <button class="back-btn" onclick={() => appState.activeToolId = null}>
    <span class="material-symbols-rounded">arrow_back</span>
    <span>全部功能</span>
  </button>

  <div class="header">
    <div class="header-left">
      <div class="icon teal">
        <span class="material-symbols-rounded">translate</span>
      </div>
      <div>
        <p class="eyebrow">语言工具</p>
        <h3>翻译机 (Free API)</h3>
      </div>
    </div>
  </div>

  <div class="lang-bar">
    <div class="lang-select">
      <select bind:value={sourceLang} onchange={translate}>
        <option value="en">英语 (English)</option>
        <option value="zh-CN">简体中文</option>
        <option value="ja">日语 (日本語)</option>
        <option value="ko">韩语 (한국어)</option>
        <option value="fr">法语 (Français)</option>
        <option value="de">德语 (Deutsch)</option>
      </select>
    </div>

    <button class="swap-btn" onclick={swapLangs}>
      <span class="material-symbols-rounded">swap_horiz</span>
    </button>

    <div class="lang-select">
      <select bind:value={targetLang} onchange={translate}>
        <option value="zh-CN">简体中文</option>
        <option value="en">英语 (English)</option>
        <option value="ja">日语 (日本語)</option>
        <option value="ko">韩语 (한국어)</option>
        <option value="fr">法语 (Français)</option>
        <option value="de">德语 (Deutsch)</option>
      </select>
    </div>
  </div>

  <div class="editor-area">
    <div class="pane">
      <div class="pane-header">
        <span class="label">原文</span>
        {#if isTranslating}
          <span class="material-symbols-rounded spinner">sync</span>
        {/if}
      </div>
      <textarea 
        class="code-input" 
        bind:value={sourceText} 
        oninput={handleInput}
        placeholder="输入要翻译的文本..."
      ></textarea>
    </div>

    <div class="pane">
      <div class="pane-header">
        <span class="label">译文</span>
        <button class="icon-action-btn" aria-label="Copy Output" onclick={handleCopy}>
          <span class="material-symbols-rounded">content_copy</span>
        </button>
      </div>
      <textarea 
        class="code-output" 
        readonly 
        value={translatedText}
        placeholder="译文将在这里呈现..."
      ></textarea>
      
      {#if errorMsg}
        <div class="error-toast">
          <span class="material-symbols-rounded">warning</span>
          <span>{errorMsg}</span>
        </div>
      {/if}
    </div>
  </div>

  <div class="footer-note">
    <span class="material-symbols-rounded">info</span>
    <p>该翻译服务使用 Google Translate 构建，基于互联网连接 (可能需要代理网络)。</p>
  </div>
</div>

<style>
  .tool-view {
    display: flex;
    flex-direction: column;
    gap: 24px;
    height: 100%;
    max-width: 1400px;
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

  .icon.teal {
    color: #30B0C7;
    background-color: rgba(48, 176, 199, 0.15);
    border-color: rgba(48, 176, 199, 0.2);
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

  .lang-bar {
    display: flex;
    align-items: center;
    gap: 24px;
    padding: 12px 24px;
    background-color: var(--bg-panel0);
    border: 1px solid var(--border-subtle);
    border-radius: var(--radius-lg);
    box-shadow: var(--shadow-sm);
  }

  .lang-select {
    flex: 1;
  }

  .lang-select select {
    width: 100%;
    padding: 10px 16px;
    font-size: 15px;
    font-weight: 600;
    color: var(--text-primary);
    background-color: var(--bg-panel1);
    border: 1px solid var(--border-subtle);
    border-radius: var(--radius-md);
    outline: none;
    cursor: pointer;
  }

  .swap-btn {
    display: grid;
    place-items: center;
    width: 44px;
    height: 44px;
    border-radius: 50%;
    background-color: var(--bg-app);
    color: var(--text-primary);
    border: 1px solid var(--border-subtle);
    transition: all 0.2s;
  }

  .swap-btn:hover {
    background-color: var(--bg-panel1);
    border-color: var(--border-focus);
    transform: rotate(180deg);
  }

  .editor-area {
    display: flex;
    gap: 24px;
    flex: 1;
    min-height: 0;
  }

  .pane {
    flex: 1;
    display: flex;
    flex-direction: column;
    background-color: var(--bg-panel0);
    border: 1px solid var(--border-subtle);
    border-radius: var(--radius-lg);
    overflow: hidden;
    position: relative;
    box-shadow: var(--shadow-sm);
  }

  .pane-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 12px 16px;
    background-color: var(--bg-panel1);
    border-bottom: 1px solid var(--border-subtle);
  }

  .label {
    font-size: 13px;
    font-weight: 600;
    color: var(--text-secondary);
  }

  .code-input, .code-output {
    flex: 1;
    width: 100%;
    padding: 20px;
    border: none;
    background: transparent;
    color: var(--text-primary);
    font-size: 16px;
    line-height: 1.6;
    resize: none;
    outline: none;
  }

  .code-output {
    background-color: var(--bg-app);
  }

  .spinner {
    font-size: 18px;
    color: var(--text-secondary);
    animation: spin 1s linear infinite;
  }

  @keyframes spin { 100% { transform: rotate(360deg); } }

  .icon-action-btn {
    color: var(--text-secondary);
    transition: color var(--transition-fast);
  }
  .icon-action-btn:hover { color: var(--text-primary); }

  .error-toast {
    position: absolute;
    bottom: 24px;
    left: 24px;
    right: 24px;
    background-color: rgba(255, 59, 48, 0.9);
    backdrop-filter: blur(10px);
    color: white;
    padding: 12px 16px;
    border-radius: 8px;
    display: flex;
    align-items: center;
    gap: 8px;
    font-size: 13px;
    box-shadow: 0 4px 12px rgba(255, 59, 48, 0.3);
  }

  .footer-note {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 8px;
    color: var(--text-caption);
    font-size: 12px;
  }

  .footer-note .material-symbols-rounded {
    font-size: 16px;
  }
</style>
