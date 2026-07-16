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
    is_masked: boolean;
  }

  interface PeekStatusResponse {
    status: string;
    cpu: number;
    memory: MemoryInfo;
    foreground_window: ForegroundWindowInfo | null;
    media: { title: string; artist: string; is_playing: boolean } | null;
  }

  interface DetectedApplication {
    title: string;
    process_name: string;
    process_id: number;
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
  let isGlobalBlurEnabled = $state(true);
  let privacyImagePath = $state<string | null>(null);
  let isToggling = $state(false);
  let serverUrl = $state('http://127.0.0.1:3000');
  let peekStatus = $state<PeekStatusResponse>(emptyStatus);
  let statusTimer: ReturnType<typeof setInterval> | undefined;
  let sensitiveRules = $state<string[]>([]);
  let sensitiveRuleText = $state('');
  let isSavingRules = $state(false);
  let ruleMessage = $state('');
  let detectedApplications = $state<DetectedApplication[]>([]);
  let isDetectingApplications = $state(false);
  let applicationSearch = $state('');

  const filteredApplications = $derived(detectedApplications.filter((application) => {
    const search = applicationSearch.trim().toLowerCase();
    return !search || application.title.toLowerCase().includes(search)
      || application.process_name.toLowerCase().includes(search);
  }));

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
    isGlobalBlurEnabled = await invoke<boolean>('get_global_blur_status');

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
    sensitiveRules = await invoke<string[]>('get_sensitive_app_rules');
    sensitiveRuleText = sensitiveRules.join('\n');
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

  const handleToggleGlobalBlur = async () => {
    isGlobalBlurEnabled = await invoke<boolean>('toggle_global_blur');
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

  const saveSensitiveRules = async () => {
    if (isSavingRules) return;
    isSavingRules = true;
    ruleMessage = '';
    try {
      const rules = sensitiveRuleText
        .split(/\r?\n|,|，/)
        .map((rule) => rule.trim())
        .filter(Boolean);
      sensitiveRules = await invoke<string[]>('set_sensitive_app_rules', { rules });
      sensitiveRuleText = sensitiveRules.join('\n');
      ruleMessage = sensitiveRules.length ? `已保存 ${sensitiveRules.length} 条规则` : '已清空程序模糊规则';
      await checkStatus();
    } catch (error) {
      console.error(error);
      ruleMessage = '保存失败';
    } finally {
      isSavingRules = false;
    }
  };

  const detectApplications = async () => {
    if (isDetectingApplications) return;
    isDetectingApplications = true;
    ruleMessage = '';
    try {
      detectedApplications = await invoke<DetectedApplication[]>('detect_peek_applications');
      ruleMessage = detectedApplications.length
        ? `检测到 ${detectedApplications.length} 个可见程序窗口，请选择要模糊的程序`
        : '没有检测到可添加的程序窗口';
    } catch (error) {
      console.error(error);
      ruleMessage = '程序检测失败';
    } finally {
      isDetectingApplications = false;
    }
  };

  const addDetectedApplication = async (application: DetectedApplication) => {
    const rules = sensitiveRuleText.split(/\r?\n/).map((rule) => rule.trim()).filter(Boolean);
    for (const candidate of [application.process_name, application.title]) {
      const rule = candidate.trim();
      if (rule && !rules.some((current) => current.toLowerCase() === rule.toLowerCase())) {
        rules.push(rule);
      }
    }

    try {
      sensitiveRules = await invoke<string[]>('set_sensitive_app_rules', { rules });
      sensitiveRuleText = sensitiveRules.join('\n');
      ruleMessage = `已添加并保存：${application.process_name || application.title}`;
      await checkStatus();
    } catch (error) {
      console.error(error);
      ruleMessage = '添加程序失败';
    }
  };
</script>

<div class="tool-content">
  <div class="tool-header">
    <div class="icon blue">
      <span class="material-symbols-rounded">cast</span>
    </div>
    <div class="title-meta">
      <h3>Peek PC 遥控监控</h3>
      <p>支持清晰截图、全局模糊和指定程序局部模糊。{isRunning ? '服务已启动' : '服务未运行'}</p>
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
        <div class="setting-copy">
          <span>常规截图全局模糊</span>
          <small>关闭后仅对命中规则的程序窗口额外模糊</small>
        </div>
        <button class="switch" class:on={isGlobalBlurEnabled} onclick={handleToggleGlobalBlur} title="切换常规全局模糊" aria-label="切换常规全局模糊">
          <div class="knob"></div>
        </button>
      </div>

      <div class="setting-row">
        <div class="setting-copy">
          <span>启用隐私遮罩</span>
          <small>强制整屏重度模糊或显示替代图片</small>
        </div>
        <button class="switch" class:on={isPrivacyEnabled} onclick={handleTogglePrivacy} title="切换隐私遮罩" aria-label="切换隐私遮罩">
          <div class="knob"></div>
        </button>
      </div>

      <div class="privacy-note">
        指定程序规则始终优先应用。隐私遮罩开启时，无论常规全局模糊开关如何，都会进一步模糊整张截图或返回替代图片。
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

    <div class="card program-privacy-card">
      <div class="card-title">
        <span class="material-symbols-rounded">blur_on</span>
        指定程序模糊
        <span class="beta-badge">试用</span>
      </div>

      <p class="program-note">
        当前版本会匹配前台程序名、可执行文件名或窗口标题，并对该窗口区域进行额外强模糊。
      </p>

      <label class="rule-editor">
        <span class="label">匹配规则（每行一个）</span>
        <textarea bind:value={sensitiveRuleText} placeholder={'QQ\nAyuGram Desktop\nfirefox.exe'}></textarea>
      </label>

      <div class="rule-actions">
        <button class="outline-btn compact" onclick={detectApplications} disabled={isDetectingApplications}>
          <span class="material-symbols-rounded">radar</span>
          {isDetectingApplications ? '检测中…' : '检测运行程序'}
        </button>
        <button class="save-rule-btn" onclick={saveSensitiveRules} disabled={isSavingRules}>
          {isSavingRules ? '保存中…' : '保存规则'}
        </button>
      </div>

      {#if detectedApplications.length}
        <div class="detected-applications">
          <div class="detected-toolbar">
            <strong>选择程序</strong>
            <input bind:value={applicationSearch} placeholder="搜索 QQ、AyuGram…" />
          </div>
          <div class="detected-list">
            {#each filteredApplications as application (`${application.process_id}-${application.title}`)}
              <div class="detected-item">
                <div class="detected-copy">
                  <strong>{application.process_name || '无法读取进程名'}</strong>
                  <span>{application.title}</span>
                  <small>PID {application.process_id}</small>
                </div>
                <button onclick={() => addDetectedApplication(application)}>添加</button>
              </div>
            {:else}
              <div class="detected-empty">没有匹配的程序</div>
            {/each}
          </div>
        </div>
      {/if}

      {#if ruleMessage}<div class="rule-message">{ruleMessage}</div>{/if}
      {#if peekStatus.foreground_window?.is_masked}
        <div class="mask-active">
          <span class="material-symbols-rounded">shield_lock</span>
          当前前台窗口已应用额外模糊
        </div>
      {/if}
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
            {peekStatus.foreground_window.is_masked ? ' · 已额外模糊' : ''}
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
    <p>关闭常规全局模糊后，截图保持清晰，仅对命中规则的前台程序窗口进行额外模糊。</p>
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

  .setting-copy {
    display: flex;
    min-width: 0;
    flex-direction: column;
    gap: 3px;
    padding-right: 12px;
  }

  .setting-copy small {
    color: var(--text-caption);
    font-size: 10px;
    font-weight: 400;
    line-height: 1.4;
  }

  .setting-row .switch { flex: 0 0 auto; }

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

  .program-note {
    margin: 0;
    color: var(--text-secondary);
    font-size: 12px;
    line-height: 1.55;
  }

  .beta-badge {
    margin-left: auto;
    padding: 3px 7px;
    border-radius: 999px;
    color: #AF52DE;
    background: rgba(175, 82, 222, 0.1);
    font-size: 10px;
  }

  .rule-editor {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .rule-editor textarea {
    box-sizing: border-box;
    width: 100%;
    height: 112px;
    padding: 11px 12px;
    resize: vertical;
    outline: none;
    border: 1px solid var(--border-subtle);
    border-radius: 12px;
    color: var(--text-primary);
    background: var(--bg-panel1);
    font: 12px/1.5 ui-monospace, SFMono-Regular, Consolas, monospace;
  }

  .rule-editor textarea:focus {
    border-color: #AF52DE;
    box-shadow: 0 0 0 3px rgba(175, 82, 222, 0.08);
  }

  .rule-actions {
    display: flex;
    gap: 8px;
  }

  .outline-btn.compact {
    flex: 1;
    border-style: solid;
  }

  .outline-btn:disabled,
  .save-rule-btn:disabled {
    opacity: 0.45;
    cursor: not-allowed;
  }

  .save-rule-btn {
    padding: 10px 14px;
    border: 0;
    border-radius: 12px;
    color: white;
    background: #AF52DE;
    cursor: pointer;
    font-size: 12px;
    font-weight: 700;
  }

  .detected-applications {
    overflow: hidden;
    border: 1px solid var(--border-subtle);
    border-radius: 12px;
    background: var(--bg-panel1);
  }

  .detected-toolbar {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 9px 10px;
    border-bottom: 1px solid var(--border-subtle);
    font-size: 11px;
  }

  .detected-toolbar input {
    min-width: 0;
    flex: 1;
    padding: 7px 9px;
    outline: none;
    border: 1px solid var(--border-subtle);
    border-radius: 8px;
    color: var(--text-primary);
    background: var(--bg-panel2);
    font-size: 11px;
  }

  .detected-list {
    max-height: 260px;
    overflow-y: auto;
  }

  .detected-item {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 10px;
    border-bottom: 1px solid var(--border-subtle);
  }

  .detected-item:last-child { border-bottom: 0; }

  .detected-copy {
    display: flex;
    min-width: 0;
    flex: 1;
    flex-direction: column;
    gap: 2px;
  }

  .detected-copy strong,
  .detected-copy span {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .detected-copy strong { font-size: 12px; }
  .detected-copy span { color: var(--text-secondary); font-size: 10px; }
  .detected-copy small { color: var(--text-caption); font-size: 9px; }

  .detected-item button {
    padding: 7px 11px;
    border: 0;
    border-radius: 9px;
    color: #AF52DE;
    background: rgba(175, 82, 222, 0.12);
    cursor: pointer;
    font-size: 11px;
    font-weight: 700;
  }

  .detected-empty {
    padding: 18px;
    color: var(--text-caption);
    text-align: center;
    font-size: 11px;
  }

  .rule-message {
    color: var(--text-caption);
    font-size: 11px;
  }

  .mask-active {
    display: flex;
    align-items: center;
    gap: 7px;
    padding: 9px 11px;
    border-radius: 11px;
    color: #248A55;
    background: rgba(52, 199, 89, 0.1);
    font-size: 11px;
    font-weight: 700;
  }

  .mask-active span { font-size: 17px; }

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
