<script lang="ts">
  import { invoke } from '@tauri-apps/api/core';
  import { onDestroy, onMount } from 'svelte';
  import { open } from '@tauri-apps/plugin-dialog';
  import { copyText } from '../tools';
  import { errorMessage, toast } from '../toast.svelte';
  import { peekQrPayload } from '../peekSecurity';

  interface MemoryInfo {
    total: number;
    used: number;
    available: number;
    usedPercent: number;
  }

  interface ForegroundWindowInfo {
    title: string;
    processName: string;
    processId: number;
    isMasked: boolean;
  }

  interface PeekStatusResponse {
    status: string;
    cpu: number;
    memory: MemoryInfo;
    foregroundWindow: ForegroundWindowInfo | null;
    media: { title: string; artist: string; is_playing: boolean } | null;
  }

  interface DetectedApplication {
    title: string;
    process_name: string;
    process_id: number;
  }

  interface PeekServerConfig { listenScope: 'lan' | 'local'; port: number }
  interface ConnectionLog { id: string; timestamp: number; ip: string; event: string; success: boolean }
  interface SecurityState { config: PeekServerConfig; apiKeyConfigured: boolean; apiKeyCreatedAt: number | null; logs: ConnectionLog[] }
  interface IssuedApiKey { apiKey: string; createdAt: number }

  const emptyStatus: PeekStatusResponse = {
    status: 'idle',
    cpu: 0,
    memory: {
      total: 0,
      used: 0,
      available: 0,
      usedPercent: 0
    },
    foregroundWindow: null,
    media: null
  };

  let isRunning = $state(false);
  let isPrivacyEnabled = $state(false);
  let isGlobalBlurEnabled = $state(true);
  let privacyImagePath = $state<string | null>(null);
  let privacyImageMessage = $state('');
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
  let securityState = $state<SecurityState>({ config: { listenScope: 'lan', port: 3000 }, apiKeyConfigured: false, apiKeyCreatedAt: null, logs: [] });
  let editScope = $state<'lan' | 'local'>('lan');
  let editPort = $state(3000);
  let qrDataUrl = $state('');
  let isSecurityBusy = $state(false);
  let issuedApiKey = $state('');

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
    try {
      const { default: QRCode } = await import('qrcode');
      qrDataUrl = await QRCode.toDataURL(peekQrPayload(serverUrl), { width: 180, margin: 1 });
    } catch { qrDataUrl = ''; }
  };

  const loadSecurity = async (syncEdit = false) => {
    securityState = await invoke<SecurityState>('get_peek_security_state');
    if (syncEdit) { editScope = securityState.config.listenScope; editPort = securityState.config.port; }
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
      peekStatus = await invoke<PeekStatusResponse>('get_peek_monitor_status');
    } catch (error) {
      console.error(error);
      peekStatus = emptyStatus;
    }
  };

  onMount(async () => {
    await refreshServerUrl();
    privacyImagePath = await invoke<string | null>('get_peek_privacy_image');
    sensitiveRules = await invoke<string[]>('get_sensitive_app_rules');
    sensitiveRuleText = sensitiveRules.join('\n');
    await loadSecurity(true);
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
        toast.info('Peek PC 服务已停止');
      } else {
        serverUrl = await invoke<string>('start_peek_server');
        isRunning = true;
        toast.success('Peek PC 安全服务已启动');
        await checkStatus();
      }
      await loadSecurity();
      await refreshServerUrl();
    } catch (error) {
      toast.error(errorMessage(error, '切换 Peek PC 服务失败'));
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
      try {
        privacyImagePath = await invoke<string | null>('set_peek_privacy_image', { path: selected });
        privacyImageMessage = '隐私图片已保存';
      } catch (error) {
        console.error(error);
        privacyImageMessage = '图片读取失败，请重新选择';
        toast.error(errorMessage(error, privacyImageMessage));
      }
    }
  };

  const handleClearImage = async () => {
    try {
      privacyImagePath = await invoke<string | null>('set_peek_privacy_image', { path: null });
      privacyImageMessage = '隐私图片已清除';
    } catch (error) {
      console.error(error);
      privacyImageMessage = '清除失败';
      toast.error(errorMessage(error, privacyImageMessage));
    }
  };

  const handleCopyUrl = async (value: string) => {
    if (await copyText(value)) toast.success('访问地址已复制');
  };

  const saveServerConfig = async () => {
    if (isRunning) { toast.error('请先停止服务再修改监听配置'); return; }
    isSecurityBusy = true;
    try {
      const config = await invoke<PeekServerConfig>('set_peek_server_config', { config: { listenScope: editScope, port: Number(editPort) } });
      securityState.config = config; await refreshServerUrl(); toast.success('Peek PC 监听配置已保存');
    } catch (error) { toast.error(errorMessage(error, '保存监听配置失败')); }
    finally { isSecurityBusy = false; }
  };

  const generateApiKey = async () => {
    if (securityState.apiKeyConfigured && !confirm('重新生成后，所有使用旧密钥的页面都会立即失效。继续吗？')) return;
    isSecurityBusy = true;
    try {
      const issued = await invoke<IssuedApiKey>('generate_peek_api_key');
      issuedApiKey = issued.apiKey;
      await loadSecurity();
      toast.success('新的 API 密钥已生成，请立即复制保存');
    } catch (error) {
      toast.error(errorMessage(error, '生成 API 密钥失败'));
    } finally {
      isSecurityBusy = false;
    }
  };

  const copyApiKey = async () => {
    if (issuedApiKey && await copyText(issuedApiKey)) toast.success('API 密钥已复制');
  };

  const clearConnectionLogs = async () => {
    try { await invoke('clear_peek_connection_logs'); await loadSecurity(); toast.success('连接日志已清空'); }
    catch (error) { toast.error(errorMessage(error, '清空日志失败')); }
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
      toast.error(errorMessage(error, ruleMessage));
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
      toast.error(errorMessage(error, ruleMessage));
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
      toast.error(errorMessage(error, ruleMessage));
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

      <button class="toggle-btn" onclick={handleToggleServer} disabled={isToggling || (!isRunning && !securityState.apiKeyConfigured)} title={!isRunning && !securityState.apiKeyConfigured ? '请先生成 API 密钥' : ''}>
        <span class="material-symbols-rounded">{isRunning ? 'stop_circle' : 'play_circle'}</span>
        {isRunning ? '停止服务端' : '启动服务端'}
      </button>
    </div>

    <div class="card security-card">
      <div class="card-title"><span class="material-symbols-rounded">shield_lock</span>安全连接</div>
      <div class="security-address">
        {#if qrDataUrl}<img src={qrDataUrl} alt="Peek PC 访问地址二维码" />{/if}
        <div><span class="label">手机访问地址</span><code>{serverUrl}</code><small>二维码只包含访问地址，不包含 API 密钥</small></div>
      </div>
      <div class="config-row">
        <label>监听范围<select bind:value={editScope} disabled={isRunning}><option value="lan">局域网</option><option value="local">仅本机</option></select></label>
        <label>端口<input type="number" min="1024" max="65535" bind:value={editPort} disabled={isRunning} /></label>
        <button class="outline-btn compact" onclick={saveServerConfig} disabled={isRunning || isSecurityBusy}>保存配置</button>
      </div>
      <div class="api-key-block">
        <div>
          <span class="label">API 密钥</span>
          {#if issuedApiKey}
            <code class="api-key-value">{issuedApiKey}</code>
            <small>该密钥只显示到关闭此工具窗口，请立即复制。</small>
          {:else if securityState.apiKeyConfigured}
            <strong>已配置</strong>
            <small>{securityState.apiKeyCreatedAt ? `生成于 ${new Date(securityState.apiKeyCreatedAt).toLocaleString()}` : '原始密钥不会保存在电脑端'}</small>
          {:else}
            <small>启动服务前需要生成一个 API 密钥。</small>
          {/if}
        </div>
        <div class="api-key-actions">
          {#if issuedApiKey}<button class="mini-btn" onclick={copyApiKey}>复制密钥</button>{/if}
          <button class="save-rule-btn" onclick={generateApiKey} disabled={isSecurityBusy}>{securityState.apiKeyConfigured ? '重新生成' : '生成密钥'}</button>
        </div>
      </div>
    </div>

    <div class="card logs-card">
      <div class="card-title log-title"><span><span class="material-symbols-rounded">history</span>连接日志</span><button class="mini-btn" onclick={clearConnectionLogs} disabled={!securityState.logs.length}>清空</button></div>
      <div class="log-list">{#each securityState.logs.slice(0, 20) as log (log.id)}<div class="log-row" class:failed={!log.success}><span>{log.event}</span><strong>{log.ip}</strong><small>{new Date(log.timestamp).toLocaleString()}</small></div>{:else}<p class="program-note">暂无连接记录</p>{/each}</div>
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
          <span>整屏重度高斯模糊</span>
          <small>开启后强制对整张截图进行更强的高斯模糊</small>
        </div>
        <button class="switch" class:on={isPrivacyEnabled} onclick={handleTogglePrivacy} title="切换整屏高斯模糊" aria-label="切换整屏高斯模糊">
          <div class="knob"></div>
        </button>
      </div>

      <div class="privacy-note">
        未设置隐私图片时使用整屏高斯模糊；设置图片后，开启隐私模式会优先显示该图片。
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
        {#if privacyImageMessage}<small class="privacy-image-message">{privacyImageMessage}</small>{/if}
      </div>
    </div>

    <div class="card program-privacy-card">
      <div class="card-title">
        <span class="material-symbols-rounded">blur_on</span>
        指定程序模糊
        <span class="beta-badge">试用</span>
      </div>

      <p class="program-note">
        检测并添加程序后，会持续枚举它的可见窗口；无论它是不是前台窗口，都会对对应区域进行额外强模糊。
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
      {#if peekStatus.foregroundWindow?.isMasked}
        <div class="mask-active">
          <span class="material-symbols-rounded">shield_lock</span>
          当前前台窗口已应用高斯模糊
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
          <strong>{peekStatus.memory.usedPercent.toFixed(1)}%</strong>
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
        {#if peekStatus.foregroundWindow}
          <strong class="window-title">{peekStatus.foregroundWindow.title || '未命名窗口'}</strong>
          <span class="window-meta">
            {peekStatus.foregroundWindow.processName || '未知进程'} · PID {peekStatus.foregroundWindow.processId}
            {peekStatus.foregroundWindow.isMasked ? ' · 已额外模糊' : ''}
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
        所有 API 都必须携带 <code>Authorization: Bearer &lt;API_KEY&gt;</code>；认证失败过多时会被临时限流。
      </p>
    </div>
  </div>

  <div class="tip-box">
    <span class="material-symbols-rounded">info</span>
    <p>关闭常规全局模糊后，截图保持清晰，仅对已添加程序的所有可见窗口进行额外模糊。</p>
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

  .privacy-image-message {
    color: var(--text-caption);
    font-size: 10px;
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
    padding: 8px 12px;
    border-radius: 10px;
    background: var(--bg-panel1);
    font-size: 13px;
  }

  .path {
    overflow: hidden;
    max-width: 180px;
    color: var(--text-primary);
    font-weight: 500;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .clear-btn {
    display: flex;
    border: none;
    color: var(--text-caption);
    background: transparent;
    cursor: pointer;
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

  .security-card,.logs-card{grid-column:span 2}.security-address{display:flex;align-items:center;gap:16px;padding:12px;border-radius:14px;background:var(--bg-panel1)}.security-address img{width:104px;height:104px;border-radius:8px}.security-address>div{min-width:0;display:flex;flex-direction:column;gap:6px}.security-address code{overflow:hidden;text-overflow:ellipsis;color:var(--text-primary)}.security-address small,.api-key-block small{color:var(--text-caption);font-size:11px}.config-row{display:grid;grid-template-columns:1fr 1fr auto;gap:10px;align-items:end}.config-row label{display:flex;flex-direction:column;gap:5px;color:var(--text-secondary);font-size:12px}.config-row input,.config-row select{width:100%;padding:8px;border:1px solid var(--border-subtle);border-radius:9px;background:var(--bg-panel1);color:var(--text-primary)}.api-key-block{display:flex;align-items:center;justify-content:space-between;gap:12px;padding:11px 0;border-top:1px solid var(--border-subtle)}.api-key-block>div:first-child{min-width:0;display:flex;flex-direction:column;gap:4px}.api-key-value{max-width:100%;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;color:#0A84FF}.api-key-actions{display:flex;flex-shrink:0;gap:8px}.log-title{justify-content:space-between}.log-title>span{display:flex;align-items:center;gap:8px}.log-list{max-height:240px;overflow:auto}.log-row{display:grid;grid-template-columns:140px 1fr auto;gap:10px;padding:8px 0;border-top:1px solid var(--border-subtle);font-size:12px}.log-row>span{color:#16a085}.log-row.failed>span{color:#e74c3c}.log-row strong{overflow:hidden;text-overflow:ellipsis;color:var(--text-primary)}.log-row small{color:var(--text-caption)}
  @media(max-width:800px){.security-card,.logs-card{grid-column:auto}.config-row{grid-template-columns:1fr}.security-address{align-items:flex-start}.api-key-block{align-items:flex-start;flex-direction:column}.log-row{grid-template-columns:100px 1fr}.log-row small{grid-column:2}}
</style>
