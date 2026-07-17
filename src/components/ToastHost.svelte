<script lang="ts">import { toastState } from '../toast.svelte';</script>
<div class="toast-host" aria-live="polite" aria-atomic="false">
  {#each toastState.messages as item (item.id)}
    <div class="toast {item.level}" role={item.level === 'error' ? 'alert' : 'status'}>
      <span class="material-symbols-rounded">{item.level === 'success' ? 'check_circle' : item.level === 'error' ? 'error' : 'info'}</span>
      <p>{item.message}</p><button onclick={() => toastState.dismiss(item.id)} aria-label="关闭通知">×</button>
    </div>
  {/each}
</div>
<style>
  .toast-host{position:fixed;right:18px;top:18px;z-index:3000;display:flex;flex-direction:column;gap:9px;pointer-events:none}.toast{pointer-events:auto;width:min(380px,calc(100vw - 32px));display:flex;align-items:center;gap:10px;padding:12px 13px;border:1px solid var(--border-subtle);border-radius:12px;background:var(--bg-app);box-shadow:0 14px 38px rgba(0,0,0,.2);animation:enter .2s ease}.toast.success>span{color:#16a085}.toast.error>span{color:#e74c3c}.toast.info>span{color:#3b82f6}.toast p{flex:1;margin:0;font-size:13px;color:var(--text-primary)}.toast button{font-size:18px;color:var(--text-secondary)}@keyframes enter{from{opacity:0;transform:translateY(-8px)}}
</style>
