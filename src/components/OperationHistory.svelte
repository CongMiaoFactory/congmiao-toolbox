<script lang="ts">
  import { onMount } from 'svelte';
  import { clearOperations, listOperations, undoOperation, type FileOperationRecord } from '../fileTools';
  let { onchanged = () => {} }: { onchanged?: () => void } = $props();
  let operations = $state<FileOperationRecord[]>([]); let busy = $state(''); let error = $state('');
  async function load() { try { operations = await listOperations(); } catch (e) { error = String(e); } }
  async function undo(record: FileOperationRecord) {
    if (!confirm(`撤销这次${record.kind === 'rename' ? '重命名' : '整理'}操作？`)) return;
    busy = record.id; error = '';
    try { await undoOperation(record.id); await load(); onchanged(); } catch (e) { error = String(e); } finally { busy = ''; }
  }
  async function clear() { if (!confirm('清空全部文件操作记录？这不会更改文件。')) return; await clearOperations(); await load(); }
  onMount(load);
</script>
<details class="history">
  <summary>最近操作与撤销</summary>
  {#if error}<p class="error">{error}</p>{/if}
  {#if operations.length === 0}<p class="empty">暂无操作记录</p>{/if}
  {#each operations as operation (operation.id)}
    <div class="row"><div><strong>{operation.kind === 'rename' ? '批量重命名' : '规则整理'}</strong><small>{new Date(operation.createdAt).toLocaleString()} · {operation.moves.length} 个文件</small></div><button disabled={operation.undone || !!busy} onclick={() => undo(operation)}>{operation.undone ? '已撤销' : busy === operation.id ? '撤销中…' : '撤销'}</button></div>
  {/each}
  {#if operations.length}<button class="clear" onclick={clear}>清空记录</button>{/if}
</details>
<style>
  .history{border-top:1px solid var(--border-subtle);padding-top:10px}summary{cursor:pointer;font-weight:600}.row{display:flex;justify-content:space-between;align-items:center;padding:8px 0;border-bottom:1px solid var(--border-subtle)}small{display:block;color:var(--text-secondary);margin-top:2px}.row button,.clear{padding:6px 12px;border-radius:8px;background:var(--bg-panel1)}.clear{margin-top:8px;color:#e74c3c}.error{color:#e74c3c}.empty{color:var(--text-secondary)}
</style>
