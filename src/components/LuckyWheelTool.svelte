<script lang="ts">
  import { onDestroy } from 'svelte';
  import { appState } from '../state.svelte';

  interface DrawOption {
    label: string;
    group?: string;
  }

  interface DrawStep {
    id: string;
    title: string;
    description: string;
    count: number;
    options: DrawOption[];
    icon: string;
    accent: string;
  }

  const colors = ['#ff5d73', '#ff9f43', '#f6c945', '#2ed573', '#2e86de', '#5f6eea', '#a55eea', '#ff6bcb', '#26c6da', '#7cb342'];

  const toOptions = (labels: string[], group?: string): DrawOption[] => labels.map((label) => ({ label, group }));

  const kalabiyauSteps: DrawStep[] = [
    {
      id: 'map',
      title: '爆破地图',
      description: '先决定本局地图',
      count: 1,
      icon: 'map',
      accent: '#2e86de',
      options: toOptions(['莱布伦城', '奥卡努斯', '科斯迷特', '柯西街区', '空间实验室', '风曳镇', '88区', '欧拉港口', '404基地'])
    },
    {
      id: 'characters',
      title: '出战角色',
      description: '抽取两名不重复角色',
      count: 2,
      icon: 'group',
      accent: '#a55eea',
      options: [
        ...toOptions(['米雪儿·李', '信', '心夏', '伊薇特', '芙拉薇娅', '忧雾', '蕾欧娜', '千代'], '欧泊'),
        ...toOptions(['明', '拉薇', '梅瑞狄斯', '令', '香奈美', '艾卡', '珐格兰丝', '玛拉', '诺诺'], '剪刀手'),
        ...toOptions(['奥黛丽', '玛德蕾娜', '绯莎', '星绘', '白墨', '加拉蒂亚', '汐'], '乌尔比诺')
      ]
    },
    {
      id: 'secondary',
      title: '副武器',
      description: '决定本局副武器',
      count: 1,
      icon: 'target',
      accent: '#ff9f43',
      options: toOptions(['小蜜蜂', '焚焰者', '雪鸮', '重焰'])
    },
    {
      id: 'prop',
      title: '战术道具',
      description: '最后抽取一件道具',
      count: 1,
      icon: 'deployed_code',
      accent: '#2ed573',
      options: toOptions(['破片手雷', '治疗雷', '烟雾弹', '闪光弹', '拦截者', '减速雷', '警报器', '风场雷', '雪球', '防弹屏障'])
    }
  ];

  let mode = $state<'preset' | 'manual'>('preset');
  let configTab = $state<'preset' | 'manual'>('preset');
  let steps = $state<DrawStep[]>(kalabiyauSteps);
  let activeStepIndex = $state(0);
  let results = $state<Record<string, string[]>>({});
  let isSpinning = $state(false);
  let autoDrawing = $state(false);
  let rotation = $state(0);
  let spinDuration = $state(3600);
  let skipTransition = $state(false);
  let lastResult = $state<DrawOption | null>(null);
  let manualTitle = $state('今天吃什么');
  let manualText = $state('火锅\n烧烤\n拉面\n轻食');
  let manualCount = $state(1);
  let manualError = $state('');
  const timers = new Set<ReturnType<typeof setTimeout>>();

  let activeStep = $derived(steps[activeStepIndex]);
  let activeResults = $derived(results[activeStep?.id] ?? []);
  let currentOptions = $derived(activeStep?.options ?? []);
  let availableOptions = $derived(currentOptions.filter((option) => !activeResults.includes(option.label)));
  let stepComplete = $derived(Boolean(activeStep && activeResults.length >= activeStep.count));
  let segmentAngle = $derived(currentOptions.length ? 360 / currentOptions.length : 0);
  let completedSteps = $derived(steps.filter((step) => (results[step.id]?.length ?? 0) >= step.count).length);
  let allComplete = $derived(completedSteps === steps.length);

  const later = (callback: () => void, delay: number) => {
    const timer = setTimeout(() => {
      timers.delete(timer);
      callback();
    }, delay);
    timers.add(timer);
  };

  const randomIndex = (length: number) => {
    if (length <= 1) return 0;
    const limit = Math.floor(0x1_0000_0000 / length) * length;
    const buffer = new Uint32Array(1);
    do crypto.getRandomValues(buffer); while (buffer[0] >= limit);
    return buffer[0] % length;
  };

  const optionColor = (option: DrawOption, index: number) => {
    if (option.group === '欧泊') return index % 2 ? '#4f7ff0' : '#6595ff';
    if (option.group === '剪刀手') return index % 2 ? '#d94c5d' : '#ef6677';
    if (option.group === '乌尔比诺') return index % 2 ? '#d9a91e' : '#edc13f';
    return colors[index % colors.length];
  };

  const spin = (afterSpin?: (completed: boolean) => void) => {
    if (isSpinning || stepComplete || !availableOptions.length) return;

    const selected = availableOptions[randomIndex(availableOptions.length)];
    const selectedIndex = currentOptions.findIndex((option) => option.label === selected.label);
    const desiredRotation = (360 - (selectedIndex * segmentAngle + segmentAngle / 2)) % 360;
    const normalizedRotation = ((rotation % 360) + 360) % 360;
    const delta = (desiredRotation - normalizedRotation + 360) % 360;

    isSpinning = true;
    spinDuration = autoDrawing ? 1800 : 3600;
    lastResult = null;
    skipTransition = false;
    rotation += (5 + randomIndex(3)) * 360 + delta;

    later(() => {
      isSpinning = false;
      lastResult = selected;
      const nextStepResults = [...activeResults, selected.label];
      results = { ...results, [activeStep.id]: nextStepResults };
      skipTransition = true;
      rotation = desiredRotation;

      appState.addActivity({
        source: 'TEXT',
        title: `${activeStep.title}：${selected.label}`,
        value: selected.group ? `阵营：${selected.group}` : mode === 'preset' ? '卡拉比丘随机模板' : '自定义抽奖',
        accent: 'blue'
      });
      afterSpin?.(nextStepResults.length >= activeStep.count);
    }, spinDuration);
  };

  const runAutoStep = () => {
    if (!autoDrawing) return;
    spin((completed) => {
      if (!autoDrawing) return;
      later(() => {
        if (!autoDrawing) return;
        if (completed) {
          if (activeStepIndex >= steps.length - 1) {
            autoDrawing = false;
            return;
          }
          goToStep(activeStepIndex + 1, true);
          later(runAutoStep, 350);
        } else {
          runAutoStep();
        }
      }, 850);
    });
  };

  const startAutoDraw = () => {
    if (isSpinning) return;
    results = {};
    activeStepIndex = 0;
    lastResult = null;
    rotation = 0;
    skipTransition = true;
    autoDrawing = true;
    later(runAutoStep, 180);
  };

  const stopAutoDraw = () => {
    autoDrawing = false;
  };

  const goToStep = (index: number, force = false) => {
    if ((!force && (isSpinning || autoDrawing)) || index < 0 || index >= steps.length) return;
    activeStepIndex = index;
    lastResult = null;
    rotation = 0;
    skipTransition = true;
  };

  const nextStep = () => {
    if (activeStepIndex < steps.length - 1) goToStep(activeStepIndex + 1);
  };

  const resetStep = () => {
    if (isSpinning || autoDrawing) return;
    const next = { ...results };
    delete next[activeStep.id];
    results = next;
    lastResult = null;
    rotation = 0;
    skipTransition = true;
  };

  const applyKalabiyauPreset = () => {
    if (isSpinning) return;
    autoDrawing = false;
    mode = 'preset';
    configTab = 'preset';
    steps = kalabiyauSteps;
    activeStepIndex = 0;
    results = {};
    lastResult = null;
    rotation = 0;
    skipTransition = true;
  };

  const applyManualDraw = () => {
    manualError = '';
    const uniqueOptions = [...new Set(manualText.split(/\r?\n|，|,/).map((item) => item.trim()).filter(Boolean))];
    if (uniqueOptions.length < 2) {
      manualError = '至少输入两个不同的选项';
      return;
    }
    const count = Math.max(1, Math.min(Math.floor(Number(manualCount) || 1), uniqueOptions.length));
    manualCount = count;
    autoDrawing = false;
    mode = 'manual';
    configTab = 'manual';
    steps = [{
      id: `manual-${Date.now()}`,
      title: manualTitle.trim() || '自定义抽奖',
      description: `从 ${uniqueOptions.length} 个选项中抽取 ${count} 个不重复结果`,
      count,
      icon: 'edit_note',
      accent: '#a55eea',
      options: toOptions(uniqueOptions)
    }];
    activeStepIndex = 0;
    results = {};
    lastResult = null;
    rotation = 0;
    skipTransition = true;
  };

  const resetAll = () => {
    if (isSpinning) return;
    autoDrawing = false;
    results = {};
    activeStepIndex = 0;
    lastResult = null;
    rotation = 0;
    skipTransition = true;
  };

  onDestroy(() => {
    for (const timer of timers) clearTimeout(timer);
    timers.clear();
  });
</script>

<div class="tool-content">
  <header class="tool-header">
    <div class="heading">
      <div class="logo"><span class="material-symbols-rounded">casino</span></div>
      <div>
        <h3>随机作战配置</h3>
        <p>{mode === 'preset' ? '卡拉比丘 · 爆破模式模板' : '自定义不重复抽奖'}</p>
      </div>
    </div>
    <div class="header-actions">
      <button class:auto-active={autoDrawing} class="auto-btn" onclick={autoDrawing ? stopAutoDraw : startAutoDraw} disabled={isSpinning && !autoDrawing}>
        <span class="material-symbols-rounded">{autoDrawing ? 'stop_circle' : 'auto_awesome'}</span>
        {autoDrawing ? '停止自动' : mode === 'preset' ? '自动抽完整套' : '自动完成抽奖'}
      </button>
      <div class="header-progress">
        <span>{completedSteps}/{steps.length} 项完成</span>
        <div><i style="width: {(completedSteps / steps.length) * 100}%"></i></div>
      </div>
    </div>
  </header>

  <div class="main-layout">
    <main class="draw-area">
      <section class="step-heading">
        <div class="step-number">{String(activeStepIndex + 1).padStart(2, '0')}</div>
        <div>
          <div class="eyebrow">当前抽取</div>
          <h2>{activeStep.title}</h2>
          <p>{activeStep.description}</p>
        </div>
        <div class="draw-count">
          <strong>{activeResults.length}</strong><span>/ {activeStep.count}</span>
        </div>
      </section>

      <section class="wheel-card">
        <div class="wheel-stage">
          <div class="pointer"><span></span></div>
          <div class="wheel" style="--spin-duration: {spinDuration}ms; transform: rotate({rotation}deg); {skipTransition ? 'transition: none;' : ''}">
            <svg viewBox="0 0 100 100" aria-label="{activeStep.title}转盘，共 {currentOptions.length} 个候选">
              {#each currentOptions as option, index}
                {@const startAngle = index * segmentAngle - 90}
                {@const endAngle = (index + 1) * segmentAngle - 90}
                {@const largeArc = segmentAngle > 180 ? 1 : 0}
                {#if currentOptions.length === 1}
                  <circle cx="50" cy="50" r="49" fill={optionColor(option, index)} />
                {:else}
                  <path
                    d="M 50 50 L {50 + 49 * Math.cos(startAngle * Math.PI / 180)} {50 + 49 * Math.sin(startAngle * Math.PI / 180)} A 49 49 0 {largeArc} 1 {50 + 49 * Math.cos(endAngle * Math.PI / 180)} {50 + 49 * Math.sin(endAngle * Math.PI / 180)} Z"
                    fill={optionColor(option, index)}
                    stroke="rgba(255,255,255,.68)"
                    stroke-width=".45"
                  />
                {/if}
                <text
                  x="50"
                  y={currentOptions.length === 1 ? 23 : currentOptions.length > 18 ? 14 : 17}
                  transform={currentOptions.length === 1 ? undefined : `rotate(${index * segmentAngle + segmentAngle / 2}, 50, 50)`}
                  fill="white"
                  font-size={currentOptions.length > 20 ? '1.9' : currentOptions.length > 12 ? '2.35' : currentOptions.length > 8 ? '2.8' : '3.5'}
                  font-weight="800"
                  text-anchor="middle"
                >{option.label.length > 8 ? `${option.label.slice(0, 7)}…` : option.label}</text>
              {/each}
            </svg>
          </div>
          <button class="spin-button" onclick={() => spin()} disabled={isSpinning || stepComplete || autoDrawing}>
            <span class="material-symbols-rounded">{isSpinning ? 'progress_activity' : stepComplete ? 'check' : 'play_arrow'}</span>
            <strong>{isSpinning ? '抽取中' : stepComplete ? '已完成' : activeStep.count > 1 ? `抽第 ${activeResults.length + 1} 个` : '开始抽取'}</strong>
          </button>
        </div>

        <div class="result-strip" aria-live="polite">
          <div class="result-copy">
            <span>{lastResult ? '本轮抽中' : stepComplete ? '本项结果' : '等待抽取'}</span>
            <strong>{lastResult?.label ?? (activeResults.length ? activeResults.join('、') : '点击转盘中心开始')}</strong>
            {#if lastResult?.group}<small>{lastResult.group}</small>{/if}
          </div>
          <div class="result-actions">
            {#if stepComplete}
              <button class="ghost-btn" onclick={resetStep} disabled={autoDrawing}><span class="material-symbols-rounded">refresh</span>重抽本项</button>
              {#if activeStepIndex < steps.length - 1}
                <button class="next-btn" onclick={nextStep} disabled={autoDrawing}>下一项<span class="material-symbols-rounded">arrow_forward</span></button>
              {/if}
            {:else if activeResults.length}
              <button class="next-btn" onclick={() => spin()}>继续抽取<span class="material-symbols-rounded">arrow_forward</span></button>
            {/if}
          </div>
        </div>
      </section>

      {#if allComplete && mode === 'preset'}
        <section class="final-summary">
          <div><span class="material-symbols-rounded">verified</span><div><strong>本局配置已生成</strong><p>地图、角色、武器和道具均已抽取完成</p></div></div>
          <button onclick={resetAll}>再来一套</button>
        </section>
      {/if}
    </main>

    <aside class="template-panel">
      <div class="tabs">
        <button class:active={configTab === 'preset'} onclick={() => configTab = 'preset'}>卡拉比丘模板</button>
        <button class:active={configTab === 'manual'} onclick={() => configTab = 'manual'}>手动输入</button>
      </div>

      {#if configTab === 'preset'}
        <div class="preset-card">
          <div class="preset-cover">
            <span class="material-symbols-rounded">sports_esports</span>
            <div><strong>爆破随机配置</strong><small>地图 → 2 名角色 → 副武器 → 道具</small></div>
            <span class="preset-tag">{mode === 'preset' ? '已套用' : '可用'}</span>
          </div>

          <div class="step-list">
            {#each kalabiyauSteps as step, index}
              {@const stepResults = mode === 'preset' ? (results[step.id] ?? []) : []}
              {@const done = stepResults.length >= step.count}
              <button class:active={mode === 'preset' && index === activeStepIndex} class:done onclick={() => mode === 'preset' && goToStep(index)}>
                <span class="step-icon" style="--accent: {step.accent}"><span class="material-symbols-rounded">{done ? 'check' : step.icon}</span></span>
                <span class="step-info"><strong>{step.title}</strong><small>{stepResults.length ? stepResults.join('、') : `${step.options.length} 个候选 · 抽 ${step.count} 个`}</small></span>
                <span class="material-symbols-rounded arrow">chevron_right</span>
              </button>
            {/each}
          </div>

          {#if mode === 'preset'}
            <button class="reset-all" onclick={resetAll} disabled={isSpinning}><span class="material-symbols-rounded">restart_alt</span>重置整套结果</button>
          {:else}
            <button class="apply-btn use-preset" onclick={applyKalabiyauPreset}><span class="material-symbols-rounded">check_circle</span>套用此模板</button>
          {/if}
        </div>
      {:else}
        <div class="manual-card">
          <label>抽奖名称<input bind:value={manualTitle} maxlength="30" placeholder="例如：今天吃什么" /></label>
          <label>候选选项<textarea bind:value={manualText} placeholder="每行一个选项，也支持逗号分隔"></textarea></label>
          <div class="manual-meta">
            <label>抽取数量<input type="number" min="1" max="10" bind:value={manualCount} /></label>
            <span>结果默认不重复</span>
          </div>
          {#if manualError}<div class="manual-error"><span class="material-symbols-rounded">error</span>{manualError}</div>{/if}
          <button class="apply-btn" onclick={applyManualDraw}>应用到转盘</button>
        </div>
      {/if}
    </aside>
  </div>
</div>

<style>
  .tool-content { container-type: inline-size; min-height: 100%; padding: 4px 6px 28px; color: var(--text-primary); }
  .tool-header, .heading, .header-actions, .header-progress, .step-heading, .result-strip, .result-actions, .preset-cover, .manual-meta, .final-summary, .final-summary > div { display: flex; align-items: center; }
  .tool-header { justify-content: space-between; gap: 20px; margin-bottom: 18px; }
  .heading { gap: 13px; }
  .logo { width: 46px; height: 46px; display: grid; place-items: center; border-radius: 14px; color: #8d55dc; background: linear-gradient(145deg, rgba(165,94,234,.2), rgba(95,110,234,.09)); }
  .logo span { font-size: 27px; }
  h2, h3, p { margin: 0; }
  .heading h3 { font-size: 20px; letter-spacing: -.02em; }
  .heading p { margin-top: 3px; color: var(--text-secondary); font-size: 12px; }
  .header-actions { gap: 12px; }
  .auto-btn { display: flex; align-items: center; gap: 6px; padding: 9px 13px; border: 0; border-radius: 11px; color: white; background: linear-gradient(135deg,#9b5de5,#6658d3); box-shadow: 0 5px 14px rgba(102,88,211,.22); cursor: pointer; font-size: 11px; font-weight: 750; white-space: nowrap; }
  .auto-btn span { font-size: 17px; }
  .auto-btn.auto-active { background: linear-gradient(135deg,#ff6b6b,#e74c6f); }
  .auto-btn:disabled { opacity: .5; cursor: not-allowed; }
  .header-progress { gap: 10px; color: var(--text-secondary); font-size: 12px; }
  .header-progress > div { width: 100px; height: 6px; overflow: hidden; border-radius: 8px; background: var(--bg-panel1); }
  .header-progress i { display: block; height: 100%; border-radius: inherit; background: linear-gradient(90deg,#a55eea,#5f6eea); transition: width .3s; }
  button, input, textarea { font: inherit; }

  .main-layout { display: grid; grid-template-columns: minmax(360px, 1fr) minmax(270px, 320px); gap: clamp(14px,2.5cqw,22px); align-items: start; }
  .draw-area { min-width: 0; }
  .step-heading { position: relative; gap: 14px; margin-bottom: 14px; }
  .step-number { color: rgba(143,82,223,.23); font-size: 42px; font-weight: 900; line-height: 1; }
  .eyebrow { margin-bottom: 2px; color: #8f52df; font-size: 10px; font-weight: 800; letter-spacing: .11em; }
  .step-heading h2 { font-size: 22px; line-height: 1.1; }
  .step-heading p { margin-top: 4px; color: var(--text-secondary); font-size: 12px; }
  .draw-count { margin-left: auto; padding: 7px 11px; border: 1px solid var(--border-subtle); border-radius: 11px; background: var(--bg-panel0); }
  .draw-count strong { color: #8f52df; font-size: 19px; }
  .draw-count span { color: var(--text-caption); font-size: 12px; }

  .wheel-card, .template-panel, .final-summary { border: 1px solid var(--border-subtle); background: var(--bg-panel0); box-shadow: var(--shadow-sm); }
  .wheel-card { padding: clamp(14px,2.5cqw,24px); border-radius: 22px; }
  .wheel-stage { position: relative; width: clamp(250px,36cqw,360px); max-width: 100%; margin: 0 auto; aspect-ratio: 1; }
  .wheel { width: 100%; height: 100%; overflow: hidden; border-radius: 50%; transition: transform var(--spin-duration, 3.6s) cubic-bezier(.12,.62,.08,1); filter: drop-shadow(0 15px 25px rgba(30,20,50,.18)); }
  .wheel svg { display: block; width: 100%; height: 100%; }
  .wheel text { paint-order: stroke; stroke: rgba(0,0,0,.2); stroke-width: .34px; stroke-linejoin: round; }
  .pointer { position: absolute; top: -10px; left: 50%; z-index: 4; width: 42px; height: 48px; transform: translateX(-50%); filter: drop-shadow(0 5px 7px rgba(0,0,0,.24)); }
  .pointer::before { content: ''; position: absolute; inset: 0; background: #24212b; clip-path: polygon(5% 0,95% 0,50% 100%); }
  .pointer span { position: absolute; top: 7px; left: 50%; width: 9px; height: 9px; border-radius: 50%; background: white; transform: translateX(-50%); }
  .spin-button { position: absolute; top: 50%; left: 50%; z-index: 3; width: 100px; height: 100px; display: grid; place-items: center; align-content: center; transform: translate(-50%,-50%); border: 9px solid rgba(255,255,255,.9); border-radius: 50%; color: white; background: linear-gradient(145deg,#9b5de5,#6658d3); box-shadow: 0 11px 26px rgba(75,52,130,.4); cursor: pointer; transition: transform .2s; }
  .spin-button:hover:not(:disabled) { transform: translate(-50%,-50%) scale(1.06); }
  .spin-button:disabled { cursor: default; opacity: .88; }
  .spin-button span { font-size: 25px; }
  .spin-button strong { max-width: 70px; font-size: 12px; line-height: 1.2; }
  .spin-button:disabled span:first-child:not(:last-child) { animation: rotate 1s linear infinite; }

  .result-strip { justify-content: space-between; gap: 18px; min-height: 68px; margin-top: 22px; padding-top: 18px; border-top: 1px solid var(--border-subtle); }
  .result-copy { min-width: 0; display: grid; grid-template-columns: auto auto; align-items: baseline; gap: 3px 10px; }
  .result-copy > span { grid-column: 1 / -1; color: var(--text-caption); font-size: 10px; font-weight: 700; }
  .result-copy strong { overflow: hidden; color: var(--text-primary); font-size: 20px; text-overflow: ellipsis; white-space: nowrap; }
  .result-copy small { padding: 3px 7px; border-radius: 99px; color: #8f52df; background: rgba(143,82,223,.1); font-size: 10px; }
  .result-actions { flex: 0 0 auto; gap: 8px; }
  .ghost-btn, .next-btn { display: flex; align-items: center; gap: 5px; padding: 9px 12px; border-radius: 10px; cursor: pointer; font-size: 12px; font-weight: 700; }
  .ghost-btn { border: 1px solid var(--border-subtle); color: var(--text-secondary); background: transparent; }
  .next-btn { border: 0; color: white; background: #8f52df; }
  .ghost-btn:disabled, .next-btn:disabled { opacity: .45; cursor: not-allowed; }
  .ghost-btn span, .next-btn span { font-size: 16px; }

  .template-panel { position: sticky; top: 0; overflow: hidden; border-radius: 20px; }
  .tabs { display: grid; grid-template-columns: 1fr 1fr; padding: 5px; border-bottom: 1px solid var(--border-subtle); background: var(--bg-panel1); }
  .tabs button { padding: 9px; border: 0; border-radius: 9px; color: var(--text-secondary); background: transparent; cursor: pointer; font-size: 12px; font-weight: 700; }
  .tabs button.active { color: var(--text-primary); background: var(--bg-panel0); box-shadow: var(--shadow-sm); }
  .preset-card, .manual-card { padding: 16px; }
  .preset-cover { position: relative; gap: 11px; padding: 14px; overflow: hidden; border-radius: 14px; color: white; background: linear-gradient(135deg,#647dee,#7f53ac); }
  .preset-cover > .material-symbols-rounded { font-size: 29px; }
  .preset-cover div { display: flex; min-width: 0; flex-direction: column; gap: 2px; }
  .preset-cover strong { font-size: 14px; }
  .preset-cover small { overflow: hidden; opacity: .78; font-size: 9px; text-overflow: ellipsis; white-space: nowrap; }
  .preset-tag { margin-left: auto; padding: 3px 6px; border-radius: 99px; background: rgba(255,255,255,.2); font-size: 9px; }
  .step-list { display: flex; flex-direction: column; gap: 5px; margin-top: 13px; }
  .step-list > button { display: grid; grid-template-columns: 37px minmax(0,1fr) auto; align-items: center; gap: 9px; width: 100%; padding: 9px; border: 1px solid transparent; border-radius: 11px; color: var(--text-primary); text-align: left; background: transparent; cursor: pointer; }
  .step-list > button:hover { background: var(--bg-panel-hover); }
  .step-list > button.active { border-color: rgba(143,82,223,.25); background: rgba(143,82,223,.07); }
  .step-icon { width: 34px; height: 34px; display: grid; place-items: center; border-radius: 10px; color: var(--accent); background: color-mix(in srgb,var(--accent) 13%,transparent); }
  .step-icon span { font-size: 18px; }
  .step-info { display: flex; min-width: 0; flex-direction: column; gap: 2px; }
  .step-info strong { font-size: 12px; }
  .step-info small { overflow: hidden; color: var(--text-caption); font-size: 9px; text-overflow: ellipsis; white-space: nowrap; }
  .step-list .arrow { color: var(--text-caption); font-size: 17px; }
  .step-list button.done .step-icon { color: #22a763; background: rgba(46,213,115,.12); }
  .reset-all { width: 100%; display: flex; justify-content: center; align-items: center; gap: 6px; margin-top: 12px; padding: 9px; border: 1px solid var(--border-subtle); border-radius: 10px; color: var(--text-secondary); background: transparent; cursor: pointer; font-size: 11px; }
  .reset-all span { font-size: 16px; }

  .manual-card { display: flex; flex-direction: column; gap: 13px; }
  .manual-card label { display: flex; flex-direction: column; gap: 6px; color: var(--text-secondary); font-size: 11px; font-weight: 700; }
  .manual-card input, .manual-card textarea { box-sizing: border-box; width: 100%; outline: 0; border: 1px solid var(--border-subtle); border-radius: 10px; color: var(--text-primary); background: var(--bg-panel1); font-size: 12px; font-weight: 400; }
  .manual-card input { height: 38px; padding: 0 11px; }
  .manual-card textarea { height: 190px; padding: 11px; resize: vertical; line-height: 1.55; }
  .manual-card input:focus, .manual-card textarea:focus { border-color: #8f52df; box-shadow: 0 0 0 3px rgba(143,82,223,.09); }
  .manual-meta { justify-content: space-between; gap: 12px; }
  .manual-meta label { width: 90px; }
  .manual-meta span { color: var(--text-caption); font-size: 10px; }
  .manual-error { display: flex; align-items: center; gap: 6px; padding: 8px 10px; border-radius: 9px; color: #d63d54; background: rgba(255,93,115,.1); font-size: 10px; }
  .manual-error span { font-size: 15px; }
  .apply-btn { display: flex; align-items: center; justify-content: center; gap: 6px; padding: 11px; border: 0; border-radius: 10px; color: white; background: linear-gradient(135deg,#9b5de5,#6658d3); cursor: pointer; font-size: 12px; font-weight: 700; }
  .apply-btn span { font-size: 17px; }
  .use-preset { width: 100%; margin-top: 12px; }

  .final-summary { justify-content: space-between; gap: 16px; margin-top: 14px; padding: 14px 17px; border-color: rgba(46,213,115,.3); border-radius: 15px; background: linear-gradient(135deg,rgba(46,213,115,.09),rgba(38,198,218,.05)); }
  .final-summary > div { gap: 10px; }
  .final-summary .material-symbols-rounded { color: #22a763; }
  .final-summary strong { font-size: 12px; }
  .final-summary p { margin-top: 2px; color: var(--text-secondary); font-size: 10px; }
  .final-summary button { padding: 8px 12px; border: 0; border-radius: 9px; color: white; background: #22a763; cursor: pointer; font-size: 11px; font-weight: 700; }
  @keyframes rotate { to { transform: rotate(360deg); } }

  @container (max-width: 760px) {
    .main-layout { grid-template-columns: 1fr; }
    .template-panel { position: static; }
    .wheel-stage { width: min(100%, 360px); }
  }
  @container (max-width: 560px) {
    .tool-header { align-items: flex-start; }
    .header-actions { align-items: flex-end; flex-direction: column-reverse; gap: 7px; }
    .header-progress { display: none; }
    .wheel-card { padding: 18px 12px; }
    .wheel-stage { width: min(100%, 320px); }
    .spin-button { width: 82px; height: 82px; border-width: 7px; }
    .result-strip { align-items: flex-start; flex-direction: column; }
    .result-actions { width: 100%; }
    .result-actions button { flex: 1; justify-content: center; }
  }
  @container (max-width: 390px) {
    .heading p, .step-heading p { display: none; }
    .logo { width: 40px; height: 40px; }
    .heading h3 { font-size: 17px; }
    .auto-btn { padding: 8px 10px; }
    .step-number { font-size: 34px; }
    .step-heading h2 { font-size: 19px; }
    .wheel-stage { width: min(100%, 280px); }
    .result-copy strong { font-size: 17px; }
  }
</style>
