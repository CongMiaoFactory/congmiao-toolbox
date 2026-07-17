<script lang="ts">
  import { invoke } from '@tauri-apps/api/core';
  import FilePlanTable from './FilePlanTable.svelte'; import OperationHistory from './OperationHistory.svelte';
  import { chooseDirectory, executePlan, type FilePlan, type RenameRule } from '../fileTools';
  let sourceDir = $state(''); let recursive = $state(false); let includeExtension = $state(false);
  let rules = $state<RenameRule[]>([{ type: 'prefix', value: '' }]); let plan = $state<FilePlan | null>(null);
  let busy = $state(false); let message = $state(''); let addType = $state<RenameRule['type']>('suffix');
  function invalidate() { plan = null; message = ''; }
  async function pick() { const value = await chooseDirectory('选择要批量重命名的目录'); if (value) { sourceDir = value; invalidate(); } }
  function addRule() {
    const rule: RenameRule = addType === 'prefix' || addType === 'suffix' ? { type: addType, value: '' }
      : addType === 'replace' ? { type: 'replace', find: '', replacement: '', caseSensitive: true }
      : addType === 'sequence' ? { type: 'sequence', start: 1, step: 1, padding: 3, position: 'suffix', separator: '_' }
      : addType === 'case' ? { type: 'case', mode: 'lower' }
      : { type: 'modifiedDate', format: 'YYYY-MM-DD', position: 'prefix', separator: '_' };
    rules = [...rules, rule]; invalidate();
  }
  function move(index: number, direction: number) { const next = index + direction; if (next < 0 || next >= rules.length) return; const copy = [...rules]; [copy[index], copy[next]] = [copy[next], copy[index]]; rules = copy; invalidate(); }
  async function preview() { busy = true; message = ''; try { plan = await invoke<FilePlan>('preview_batch_rename', { request: { sourceDir, recursive, includeExtension, rules } }); if (!plan.entries.length) message = '目录中没有可处理的普通文件。'; } catch (e) { message = String(e); } finally { busy = false; } }
  async function execute() { if (!plan || !confirm(`确认重命名 ${plan.readyCount} 个文件？`)) return; busy = true; try { const result = await executePlan(plan.planId); message = `已重命名 ${result.moves.length} 个文件，可在操作记录中撤销。`; plan = null; } catch (e) { message = String(e); } finally { busy = false; } }
</script>

<div class="tool"><header><div><p>安全文件工具</p><h2>批量重命名</h2></div><span class="safe">预览后执行 · 永不覆盖</span></header>
  <section class="source"><input readonly value={sourceDir} placeholder="请选择目录"/><button onclick={pick}>选择目录</button><label><input type="checkbox" bind:checked={recursive} onchange={invalidate}/>递归子目录</label><label><input type="checkbox" bind:checked={includeExtension} onchange={invalidate}/>包含扩展名</label></section>
  <section class="rules"><div class="section-title"><strong>规则链</strong><div><select bind:value={addType}><option value="prefix">前缀</option><option value="suffix">后缀</option><option value="replace">查找替换</option><option value="sequence">序号</option><option value="case">大小写</option><option value="modifiedDate">修改日期</option></select><button onclick={addRule}>添加规则</button></div></div>
    {#each rules as rule, index (index)}
      <div class="rule"><span class="order">{index + 1}</span><strong>{rule.type === 'prefix' ? '添加前缀' : rule.type === 'suffix' ? '添加后缀' : rule.type === 'replace' ? '查找替换' : rule.type === 'sequence' ? '添加序号' : rule.type === 'case' ? '转换大小写' : '修改日期'}</strong>
        {#if rule.type === 'prefix' || rule.type === 'suffix'}<input bind:value={rule.value} oninput={invalidate} placeholder="输入文本"/>
        {:else if rule.type === 'replace'}<input bind:value={rule.find} oninput={invalidate} placeholder="查找"/><input bind:value={rule.replacement} oninput={invalidate} placeholder="替换为"/><label><input type="checkbox" bind:checked={rule.caseSensitive} onchange={invalidate}/>区分大小写</label>
        {:else if rule.type === 'sequence'}<label>起始<input type="number" bind:value={rule.start} oninput={invalidate}/></label><label>步长<input type="number" bind:value={rule.step} oninput={invalidate}/></label><label>位数<input type="number" min="0" max="12" bind:value={rule.padding} oninput={invalidate}/></label><select bind:value={rule.position} onchange={invalidate}><option value="prefix">前置</option><option value="suffix">后置</option></select><input class="short" bind:value={rule.separator} oninput={invalidate} placeholder="分隔符"/>
        {:else if rule.type === 'case'}<select bind:value={rule.mode} onchange={invalidate}><option value="lower">小写</option><option value="upper">大写</option></select>
        {:else}<select bind:value={rule.format} onchange={invalidate}><option value="YYYY-MM-DD">YYYY-MM-DD</option><option value="YYYYMMDD">YYYYMMDD</option></select><select bind:value={rule.position} onchange={invalidate}><option value="prefix">前置</option><option value="suffix">后置</option></select><input class="short" bind:value={rule.separator} oninput={invalidate} placeholder="分隔符"/>{/if}
        <div class="actions"><button onclick={() => move(index,-1)}>↑</button><button onclick={() => move(index,1)}>↓</button><button onclick={() => { rules = rules.filter((_,i) => i !== index); invalidate(); }}>×</button></div>
      </div>
    {/each}
  </section>
  <div class="toolbar"><button class="preview" disabled={!sourceDir || !rules.length || busy} onclick={preview}>{busy ? '处理中…' : '生成预览'}</button><button class="execute" disabled={!plan || plan.invalidCount > 0 || plan.readyCount === 0 || busy} onclick={execute}>确认执行</button>{#if message}<span class:error={message.includes('失败') || message.includes('错误')}>{message}</span>{/if}</div>
  <FilePlanTable {plan}/><OperationHistory onchanged={invalidate}/>
</div>

<style>
  .tool{height:100%;display:flex;flex-direction:column;gap:14px;overflow:auto;padding:2px}header,.section-title,.toolbar,.source,.rule{display:flex;align-items:center;gap:10px}header{justify-content:space-between}header p{color:var(--text-secondary);font-size:12px}h2{font-size:24px}.safe{color:#16a085;background:rgba(22,160,133,.12);padding:6px 10px;border-radius:999px;font-size:12px}.source,.rules{padding:12px;border:1px solid var(--border-subtle);border-radius:12px;background:var(--bg-panel0)}.source>input{flex:1}.source label,.rule label{display:flex;align-items:center;gap:5px;font-size:12px}.section-title{justify-content:space-between;margin-bottom:10px}.section-title>div{display:flex;gap:6px}.rule{padding:8px 0;border-top:1px solid var(--border-subtle);flex-wrap:wrap}.rule>input{min-width:100px;flex:1}.rule label input[type=number]{width:70px}.short{max-width:72px}.order{width:24px;height:24px;display:grid;place-items:center;border-radius:50%;background:var(--bg-panel1)}.actions{margin-left:auto;display:flex}.actions button{padding:4px 7px}.toolbar span{font-size:12px;color:var(--text-secondary)}.error{color:#e74c3c!important}input,select,button{border:1px solid var(--border-subtle);border-radius:8px;padding:7px 9px;background:var(--bg-panel1);color:var(--text-primary)}button{cursor:pointer}.preview{background:#3b82f6;color:white}.execute{background:#16a085;color:white}button:disabled{opacity:.45;cursor:not-allowed}
</style>
