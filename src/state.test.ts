import { beforeEach, describe, expect, it, vi } from 'vitest';
import { defaultTimerSnapshot, type PersistedWorkspaceV1 } from './workspace';

const { loadWorkspace, saveWorkspace } = vi.hoisted(() => ({
  loadWorkspace: vi.fn<() => Promise<PersistedWorkspaceV1 | null>>(),
  saveWorkspace: vi.fn<(workspace: PersistedWorkspaceV1) => Promise<void>>(),
}));
vi.mock('./persistence', () => ({ loadWorkspace, saveWorkspace }));

import { AppState } from './state.svelte';

beforeEach(() => {
  vi.useFakeTimers();
  loadWorkspace.mockReset();
  saveWorkspace.mockReset().mockResolvedValue(undefined);
});

describe('AppState persistence', () => {
  it('hydrates preferences, todos and window state', async () => {
    loadWorkspace.mockResolvedValue({
      schemaVersion: 1,
      savedAt: 1,
      preferences: { theme: 'dark', bgImageUrl: 'data:image/webp;base64,test', bgBlur: 12, sidebarCollapsed: false },
      desktop: {
        activeNavIndex: 1,
        activeWindowId: 'window-1',
        windows: [{
          id: 'window-1', toolId: 'json', x: 20, y: 30, width: 800, height: 600,
          zIndex: 10, isMinimized: true, isMaximized: false, restoreGeometry: null,
        }],
      },
      todos: [{ id: 'todo-1', text: 'persist me', done: false }],
      timers: defaultTimerSnapshot(),
    });
    const state = new AppState();
    await state.hydrate({ width: 1000, height: 700 });

    expect(state.theme).toBe('dark');
    expect(state.todos).toHaveLength(1);
    expect(state.windows[0]).toMatchObject({ toolId: 'json', isMinimized: true });
  });

  it('persists todo mutations after the debounce', async () => {
    loadWorkspace.mockResolvedValue(null);
    const state = new AppState();
    await state.hydrate({ width: 1000, height: 700 });
    state.addTodo('new task');
    await vi.advanceTimersByTimeAsync(300);

    expect(saveWorkspace).toHaveBeenCalledOnce();
    expect(saveWorkspace.mock.calls[0][0].todos[0].text).toBe('new task');
  });

  it('minimizes, restores and maximizes a registered window', async () => {
    loadWorkspace.mockResolvedValue(null);
    const state = new AppState();
    await state.hydrate({ width: 1000, height: 700 });
    state.openFloatingWindow('timer');
    const id = state.windows[0].id;
    state.minimizeWindow(id);
    expect(state.windows[0].isMinimized).toBe(true);
    state.restoreWindow(id);
    expect(state.windows[0].isMinimized).toBe(false);
    state.toggleWindowMaximize(id);
    expect(state.windows[0].isMaximized).toBe(true);
    state.toggleWindowMaximize(id);
    expect(state.windows[0].isMaximized).toBe(false);
  });

  it('saves and applies a workspace template without replacing todos', async () => {
    loadWorkspace.mockResolvedValue(null);
    const state = new AppState();
    await state.hydrate({ width: 1000, height: 700 });
    state.addTodo('keep me');
    state.openFloatingWindow('json');
    state.theme = 'dark';
    const template = state.saveWorkspaceTemplate('开发');
    state.closeWindow(state.windows[0].id);
    state.theme = 'light';

    state.applyWorkspaceTemplate(template.id);
    expect(state.theme).toBe('dark');
    expect(state.windows[0].toolId).toBe('json');
    expect(state.todos[0].text).toBe('keep me');
  });

  it('tracks favorites and bounded recent tool usage', async () => {
    loadWorkspace.mockResolvedValue(null);
    const state = new AppState();
    await state.hydrate({ width: 1000, height: 700 });
    state.toggleFavorite('timer');
    state.recordToolUsage('timer');
    state.recordToolUsage('timer');
    expect(state.favorites).toEqual(['timer']);
    expect(state.recentTools[0]).toMatchObject({ id: 'timer', useCount: 2 });
  });
});
