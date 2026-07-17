<script lang="ts">
  import { appState } from '../state.svelte';
  import { getTool } from '../toolRegistry';
  import { errorMessage, toast } from '../toast.svelte';

  let templateName = $state('');

  function saveTemplate() {
    try {
      const template = appState.saveWorkspaceTemplate(templateName);
      templateName = '';
      toast.success(`工作区“${template.name}”已保存`);
    } catch (error) { toast.error(errorMessage(error, '保存工作区失败')); }
  }

  function applyTemplate(id: string, name: string) {
    try {
      appState.applyWorkspaceTemplate(id);
      appState.settingsOpen = false;
      toast.success(`已切换到工作区“${name}”`);
    } catch (error) { toast.error(errorMessage(error, '应用工作区失败')); }
  }

  function overwriteTemplate(id: string, name: string) {
    if (!confirm(`使用当前桌面覆盖工作区“${name}”？`)) return;
    try { appState.overwriteWorkspaceTemplate(id); toast.success('工作区模板已更新'); }
    catch (error) { toast.error(errorMessage(error, '更新工作区失败')); }
  }

  function renameTemplate(id: string, currentName: string) {
    const name = prompt('输入新的工作区名称', currentName);
    if (name === null || name.trim() === currentName) return;
    try { appState.renameWorkspaceTemplate(id, name); toast.success('工作区已重命名'); }
    catch (error) { toast.error(errorMessage(error, '重命名失败')); }
  }

  function deleteTemplate(id: string, name: string) {
    if (!confirm(`删除工作区模板“${name}”？此操作不会关闭当前窗口。`)) return;
    appState.deleteWorkspaceTemplate(id);
    toast.info('工作区模板已删除');
  }
</script>

<div class="workspace-create">
  <input bind:value={templateName} maxlength="40" placeholder="例如：开发、学习、文件整理" onkeydown={(event) => { if (event.key === 'Enter') saveTemplate(); }} />
  <button class="primary" onclick={saveTemplate} disabled={!templateName.trim()}>保存当前桌面</button>
</div>
<p class="workspace-note">保存窗口布局、主题、壁纸和计时器预设，不保存待办内容。最多 20 个模板。</p>

<div class="template-list">
  {#each appState.workspaceTemplates as template (template.id)}
    <article>
      <div class="template-icon"><span class="material-symbols-rounded">space_dashboard</span></div>
      <div class="template-info">
        <strong>{template.name}</strong>
        <span>{template.desktop.windows.length} 个窗口 · {template.desktop.windows.map((window) => getTool(window.toolId)?.title).filter(Boolean).join('、') || '空桌面'}</span>
        <small>更新于 {new Date(template.updatedAt).toLocaleString()}</small>
      </div>
      <div class="template-actions">
        <button onclick={() => applyTemplate(template.id, template.name)}>应用</button>
        <button onclick={() => overwriteTemplate(template.id, template.name)}>覆盖</button>
        <button onclick={() => renameTemplate(template.id, template.name)} aria-label="重命名"><span class="material-symbols-rounded">edit</span></button>
        <button class="danger" onclick={() => deleteTemplate(template.id, template.name)} aria-label="删除"><span class="material-symbols-rounded">delete</span></button>
      </div>
    </article>
  {:else}
    <div class="empty">还没有工作区模板。整理好窗口后保存一个吧。</div>
  {/each}
</div>

<style>
  .workspace-create{display:flex;gap:8px}.workspace-create input{flex:1;min-width:0;padding:9px 11px;border:1px solid var(--border-subtle);border-radius:9px;background:var(--bg-app);color:var(--text-primary)}button{border:1px solid var(--border-subtle);border-radius:8px;padding:7px 10px;background:var(--bg-app);color:var(--text-secondary);cursor:pointer}button:hover{background:var(--bg-panel-hover);color:var(--text-primary)}button:disabled{opacity:.5;cursor:not-allowed}.primary{background:#0a84ff;border-color:#0a84ff;color:white;font-weight:600}.workspace-note{margin:0;color:var(--text-caption);font-size:12px}.template-list{display:flex;flex-direction:column;gap:8px}.template-list article{display:grid;grid-template-columns:auto minmax(0,1fr) auto;gap:11px;align-items:center;padding:11px;border:1px solid var(--border-subtle);border-radius:11px;background:var(--bg-panel0)}.template-icon{display:grid;place-items:center;width:38px;height:38px;border-radius:10px;background:rgba(175,82,222,.12);color:#af52de}.template-info{display:flex;min-width:0;flex-direction:column;gap:3px}.template-info strong{color:var(--text-primary)}.template-info span,.template-info small{overflow:hidden;text-overflow:ellipsis;white-space:nowrap;color:var(--text-caption);font-size:11px}.template-actions{display:flex;gap:5px}.template-actions button{padding:6px 8px}.template-actions span{font-size:17px}.template-actions .danger{color:#e74c3c}.empty{padding:20px;text-align:center;color:var(--text-caption);font-size:12px}@media(max-width:650px){.template-list article{grid-template-columns:auto minmax(0,1fr)}.template-actions{grid-column:2;flex-wrap:wrap}.workspace-create{flex-direction:column}}
</style>
