<script lang="ts">
  type Todo = {
    id: string;
    text: string;
    done: boolean;
  };

  let todos = $state<Todo[]>([
    { id: '1', text: '完成重构为桌面形态', done: false },
    { id: '2', text: '测试各个小组件', done: false }
  ]);
  let newTodoText = $state('');

  function addTodo(e: KeyboardEvent) {
    if (e.key === 'Enter' && newTodoText.trim()) {
      todos.push({
        id: crypto.randomUUID(),
        text: newTodoText.trim(),
        done: false
      });
      newTodoText = '';
    }
  }

  function toggleTodo(id: string) {
    const todo = todos.find(t => t.id === id);
    if (todo) todo.done = !todo.done;
  }

  function deleteTodo(id: string) {
    todos = todos.filter(t => t.id !== id);
  }
</script>

<div class="todo-widget">
  <div class="header">
    <h3>待办事项</h3>
    <span class="count">{todos.filter(t => t.done).length}/{todos.length}</span>
  </div>
  
  <div class="todo-list">
    {#each todos as todo (todo.id)}
      <div class="todo-item" class:done={todo.done}>
        <button class="checkbox" onclick={() => toggleTodo(todo.id)}>
          {#if todo.done}
            <span class="material-symbols-rounded">check</span>
          {/if}
        </button>
        <span class="text">{todo.text}</span>
        <button class="delete" onclick={() => deleteTodo(todo.id)}>
          <span class="material-symbols-rounded">close</span>
        </button>
      </div>
    {/each}
  </div>

  <div class="input-area">
    <input 
      type="text" 
      placeholder="添加新任务... (回车确认)" 
      bind:value={newTodoText}
      onkeydown={addTodo}
    />
  </div>
</div>

<style>
  .todo-widget {
    background-color: var(--bg-panel0, rgba(255, 255, 255, 0.8));
    backdrop-filter: blur(10px);
    border: 1px solid var(--border-subtle, rgba(0, 0, 0, 0.1));
    border-radius: var(--radius-xl, 20px);
    padding: 20px;
    display: flex;
    flex-direction: column;
    gap: 16px;
    box-shadow: var(--shadow-md, 0 4px 6px rgba(0,0,0,0.1));
    height: 100%;
    max-height: 400px;
  }

  :global([data-theme="dark"]) .todo-widget {
    background-color: var(--bg-panel0, rgba(30, 30, 30, 0.8));
    border-color: var(--border-subtle, rgba(255, 255, 255, 0.1));
  }

  .header {
    display: flex;
    justify-content: space-between;
    align-items: center;
  }

  .header h3 {
    margin: 0;
    font-size: 16px;
    color: var(--text-primary, #333);
  }

  .header .count {
    font-size: 12px;
    color: var(--text-secondary, #666);
    background: var(--bg-element, #eee);
    padding: 2px 8px;
    border-radius: 12px;
  }

  .todo-list {
    flex: 1;
    overflow-y: auto;
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .todo-item {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 8px;
    border-radius: 8px;
    transition: background-color 0.2s;
  }

  .todo-item:hover {
    background-color: var(--bg-panel-hover, rgba(0,0,0,0.05));
  }

  :global([data-theme="dark"]) .todo-item:hover {
    background-color: var(--bg-panel-hover, rgba(255,255,255,0.05));
  }

  .todo-item.done .text {
    text-decoration: line-through;
    color: var(--text-secondary, #999);
  }

  .checkbox {
    width: 20px;
    height: 20px;
    border-radius: 6px;
    border: 2px solid var(--border-focus, #007AFF);
    background: transparent;
    display: flex;
    align-items: center;
    justify-content: center;
    cursor: pointer;
    padding: 0;
    color: var(--border-focus, #007AFF);
  }

  .todo-item.done .checkbox {
    background: var(--border-focus, #007AFF);
    color: white;
  }

  .checkbox span {
    font-size: 14px;
    font-weight: bold;
  }

  .text {
    flex: 1;
    font-size: 14px;
    color: var(--text-primary, #333);
  }

  :global([data-theme="dark"]) .text {
    color: var(--text-primary, #eee);
  }

  .delete {
    background: transparent;
    border: none;
    color: var(--text-secondary, #999);
    cursor: pointer;
    opacity: 0;
    padding: 4px;
    border-radius: 4px;
  }

  .todo-item:hover .delete {
    opacity: 1;
  }

  .delete:hover {
    background: rgba(255, 59, 48, 0.1);
    color: #FF3B30;
  }

  .input-area input {
    width: 100%;
    padding: 10px 12px;
    border-radius: 8px;
    border: 1px solid var(--border-subtle, #ccc);
    background: var(--bg-input, #fff);
    color: var(--text-primary, #333);
    font-size: 14px;
    box-sizing: border-box;
  }

  :global([data-theme="dark"]) .input-area input {
    background: var(--bg-input, #222);
    border-color: var(--border-subtle, #444);
    color: var(--text-primary, #eee);
  }

  .input-area input:focus {
    outline: none;
    border-color: var(--border-focus, #007AFF);
  }
</style>
