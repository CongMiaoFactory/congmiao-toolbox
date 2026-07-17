<script lang="ts">
  import { formatBytes, type FilePlan } from '../fileTools';
  let { plan }: { plan: FilePlan | null } = $props();
</script>

{#if plan}
  <div class="plan-summary">
    <span class="ready">可执行 {plan.readyCount}</span>
    <span class:danger={plan.invalidCount > 0}>冲突 {plan.invalidCount}</span>
    <span>未变化 {plan.entries.length - plan.readyCount - plan.invalidCount}</span>
  </div>
  <div class="table-wrap">
    <table>
      <thead><tr><th>原名称</th><th>目标名称</th><th>大小</th><th>状态</th></tr></thead>
      <tbody>
        {#each plan.entries.slice(0, 1000) as entry (entry.sourcePath)}
          <tr class:invalid={entry.status === 'invalid'}>
            <td title={entry.sourcePath}>{entry.originalName}</td>
            <td title={entry.targetPath}>{entry.targetName}</td>
            <td>{formatBytes(entry.size)}</td>
            <td>{entry.reason ?? (entry.status === 'ready' ? '就绪' : '未变化')}</td>
          </tr>
        {/each}
      </tbody>
    </table>
    {#if plan.entries.length > 1000}<p class="limit">仅显示前 1000 项，执行仍包含全部项目。</p>{/if}
  </div>
{/if}

<style>
  .plan-summary{display:flex;gap:10px;align-items:center}.plan-summary span{padding:5px 10px;border-radius:999px;background:var(--bg-panel1);font-size:12px}.ready{color:#16a085}.danger{color:#e74c3c!important;background:rgba(231,76,60,.12)!important}
  .table-wrap{overflow:auto;border:1px solid var(--border-subtle);border-radius:12px;min-height:160px}table{width:100%;border-collapse:collapse;font-size:12px}th,td{padding:9px 12px;text-align:left;border-bottom:1px solid var(--border-subtle);max-width:280px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}th{position:sticky;top:0;background:var(--bg-panel0);z-index:1;color:var(--text-secondary)}tr.invalid{background:rgba(231,76,60,.08)}.limit{padding:8px 12px;color:var(--text-secondary)}
</style>
