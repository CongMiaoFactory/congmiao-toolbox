<script lang="ts">
  import { invoke } from '@tauri-apps/api/core';
  import FilePlanTable from './FilePlanTable.svelte'; import OperationHistory from './OperationHistory.svelte';
  import { chooseDirectory, executePlan, type FilePlan } from '../fileTools';
  type Mapping = { extension: string; folder: string };
  let sourceDir = $state(''); let targetDir = $state(''); let recursive = $state(false); let mode = $state<'extension'|'modifiedDate'|'size'>('extension');
  let granularity = $state<'year'|'month'>('month'); let smallMb = $state(10); let largeMb = $state(100); let mappings = $state<Mapping[]>([]);
  let plan = $state<FilePlan|null>(null); let busy = $state(false); let message = $state('');
  function invalidate(){plan=null;message=''}
  async function pickSource(){const value=await chooseDirectory('选择待整理目录');if(value){sourceDir=value;if(!targetDir)targetDir=value;invalidate()}}
  async function pickTarget(){const value=await chooseDirectory('选择整理目标目录');if(value){targetDir=value;invalidate()}}
  function requestMode(){return mode==='extension'?{type:'extension'}:mode==='modifiedDate'?{type:'modifiedDate',granularity}:{type:'size',smallBytes:smallMb*1024**2,largeBytes:largeMb*1024**2}}
  async function preview(){busy=true;message='';try{plan=await invoke<FilePlan>('preview_file_organize',{request:{sourceDir,targetDir,recursive,mode:requestMode(),customMappings:mappings}});if(!plan.entries.length)message='目录中没有可整理的普通文件。'}catch(e){message=String(e)}finally{busy=false}}
  async function execute(){if(!plan||!confirm(`确认移动 ${plan.readyCount} 个文件？`))return;busy=true;try{const result=await executePlan(plan.planId);message=`已整理 ${result.moves.length} 个文件，可在操作记录中撤销。`;plan=null}catch(e){message=String(e)}finally{busy=false}}
</script>
<div class="tool"><header><div><p>安全文件工具</p><h2>规则整理文件</h2></div><span>移动前完整预览</span></header>
  <section class="paths"><label>源目录<div><input readonly value={sourceDir} placeholder="请选择目录"/><button onclick={pickSource}>选择</button></div></label><label>目标目录<div><input readonly value={targetDir} placeholder="默认使用源目录"/><button onclick={pickTarget}>选择</button></div></label><label class="check"><input type="checkbox" bind:checked={recursive} onchange={invalidate}/>递归子目录（自动排除目标目录）</label></section>
  <section class="settings"><strong>整理方式</strong><div class="modes"><label class:active={mode==='extension'}><input type="radio" bind:group={mode} value="extension" onchange={invalidate}/>扩展类型</label><label class:active={mode==='modifiedDate'}><input type="radio" bind:group={mode} value="modifiedDate" onchange={invalidate}/>修改日期</label><label class:active={mode==='size'}><input type="radio" bind:group={mode} value="size" onchange={invalidate}/>文件大小</label></div>
    {#if mode==='modifiedDate'}<label>目录粒度 <select bind:value={granularity} onchange={invalidate}><option value="month">年份-月份</option><option value="year">年份</option></select></label>{/if}
    {#if mode==='size'}<div class="threshold"><label>小文件上限 <input type="number" min="1" bind:value={smallMb} oninput={invalidate}/> MB</label><label>大文件起点 <input type="number" min="2" bind:value={largeMb} oninput={invalidate}/> MB</label></div>{/if}
  </section>
  <section class="mapping"><div class="title"><div><strong>自定义扩展名映射</strong><small>优先于内置分类</small></div><button onclick={()=>{mappings=[...mappings,{extension:'',folder:''}];invalidate()}}>添加映射</button></div>
    {#each mappings as mapping,index (index)}<div class="map-row"><input bind:value={mapping.extension} oninput={invalidate} placeholder="扩展名，如 psd"/><span>→</span><input bind:value={mapping.folder} oninput={invalidate} placeholder="相对文件夹，如 设计/源文件"/><button onclick={()=>{mappings=mappings.filter((_,i)=>i!==index);invalidate()}}>删除</button></div>{/each}
  </section>
  <div class="toolbar"><button class="preview" disabled={!sourceDir||!targetDir||busy} onclick={preview}>{busy?'处理中…':'生成预览'}</button><button class="execute" disabled={!plan||plan.invalidCount>0||plan.readyCount===0||busy} onclick={execute}>确认移动</button>{#if message}<span>{message}</span>{/if}</div>
  <FilePlanTable {plan}/><OperationHistory onchanged={invalidate}/>
</div>
<style>
  .tool{height:100%;display:flex;flex-direction:column;gap:14px;overflow:auto;padding:2px}header{display:flex;justify-content:space-between;align-items:center}header p,small,.toolbar span{color:var(--text-secondary);font-size:12px}header span{color:#16a085;background:rgba(22,160,133,.12);padding:6px 10px;border-radius:999px}h2{font-size:24px}.paths,.settings,.mapping{border:1px solid var(--border-subtle);border-radius:12px;padding:12px;background:var(--bg-panel0)}.paths{display:grid;grid-template-columns:1fr 1fr;gap:10px}.paths label>div{display:flex;margin-top:5px}.paths input[readonly]{flex:1}.check{grid-column:1/-1;display:flex;gap:6px}.modes,.threshold,.toolbar,.title,.map-row{display:flex;align-items:center;gap:10px}.modes{margin:10px 0}.modes label{padding:8px 12px;border-radius:9px;background:var(--bg-panel1)}.modes label.active{outline:2px solid #3b82f6}.threshold{margin-top:10px}.threshold input{width:90px}.title{justify-content:space-between}.title small{display:block}.map-row{margin-top:8px}.map-row input{flex:1}.toolbar span{overflow:hidden;text-overflow:ellipsis}.preview{background:#3b82f6!important;color:white!important}.execute{background:#16a085!important;color:white!important}input,select,button{border:1px solid var(--border-subtle);border-radius:8px;padding:7px 9px;background:var(--bg-panel1);color:var(--text-primary)}button{cursor:pointer}button:disabled{opacity:.45}
</style>
