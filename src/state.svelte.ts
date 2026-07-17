import { getTool, migrateWindowToolId, type ToolId, type WindowToolId } from './toolRegistry';
import { loadWorkspace, saveWorkspace } from './persistence';
import {
  DEFAULT_WALLPAPER,
  WORKSPACE_SCHEMA_VERSION,
  clampGeometry,
  defaultTimerSnapshot,
  reconcileTimers,
  type PersistedWorkspaceV1,
  type TodoItem,
  type WindowGeometry,
} from './workspace';

export type { ToolId } from './toolRegistry';
export type { TodoItem } from './workspace';

export type NavItem = { title: string; caption: string; icon: string };
export type ActivityEntry = {
  source: 'TEXT' | 'FILE' | 'SYSTEM';
  title: string;
  value: string;
  meta: string;
  accent: 'teal' | 'blue';
};
export type SettingsGroup = { title: string; items: string[] };

export interface WindowData extends WindowGeometry {
  id: string;
  toolId: WindowToolId;
  title: string;
  minWidth: number;
  minHeight: number;
  isMinimized: boolean;
  isMaximized: boolean;
  restoreGeometry: WindowGeometry | null;
  zIndex: number;
}

export const navItems: NavItem[] = [
  { title: '仪表盘', caption: '添加小组件 / 快捷跳转', icon: 'dashboard' },
  { title: '全部工具', caption: '工具集列表', icon: 'apps' },
  { title: '使用时长', caption: '应用屏幕使用时间', icon: 'schedule' },
];

export const settingsGroups: SettingsGroup[] = [
  { title: 'Stack', items: ['Svelte 5', 'Tauri 2', 'Bun', 'Rust'] },
  { title: 'Workspace', items: ['持久化窗口', '计时恢复', '本地壁纸'] },
  { title: 'Automation', items: ['Cmd/Ctrl+K', 'Clipboard Actions', 'Auto Update'] },
];

export function formatMeta() {
  return new Date().toLocaleTimeString('zh-CN', {
    hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false,
  });
}

export class AppState {
  appVersion = $state('0.2.8');
  ready = $state(false);
  theme = $state<'dark' | 'light'>('light');
  bgImageUrl = $state(DEFAULT_WALLPAPER);
  bgBlur = $state(0);
  sidebarCollapsed = $state(true);
  activeNavIndex = $state(0);
  activeToolId = $state<string | null>(null);
  settingsOpen = $state(false);
  commandOpen = $state(false);
  commandQuery = $state('');
  commandIndex = $state(0);

  currentUnix = $state(Math.floor(Date.now() / 1000));
  clipboardJsonReady = $state(false);
  clipboardJsonHint = $state('剪贴板暂未检测到 JSON');
  clipboardJsonPreview = $state('{ ... }');
  timestampDropActive = $state(false);
  timestampFlash = $state(false);
  jsonFlash = $state(false);
  activeToolPulse = $state<ToolId | null>(null);

  windows = $state<WindowData[]>([]);
  activeWindowId = $state<string | null>(null);
  todos = $state<TodoItem[]>([]);
  timers = $state(defaultTimerSnapshot());

  recentActivity = $state<ActivityEntry[]>([{
    source: 'SYSTEM', title: 'Workspace Ready', value: '等待操作', meta: formatMeta(), accent: 'teal',
  }]);

  private persistTimer: number | null = null;
  private persistQueue: Promise<void> = Promise.resolve();

  async hydrate(viewport = this.viewport()) {
    const workspace = await loadWorkspace();
    if (workspace) {
      this.theme = workspace.preferences.theme;
      this.bgImageUrl = workspace.preferences.bgImageUrl || DEFAULT_WALLPAPER;
      this.bgBlur = Math.min(100, Math.max(0, workspace.preferences.bgBlur));
      this.sidebarCollapsed = workspace.preferences.sidebarCollapsed;
      this.activeNavIndex = Math.min(2, Math.max(0, workspace.desktop.activeNavIndex));
      this.todos = workspace.todos.filter((todo) => todo.text.trim()).slice(0, 500);
      this.timers = reconcileTimers(workspace.timers);
      this.windows = workspace.desktop.windows.flatMap((saved) => {
        const toolId = migrateWindowToolId(saved.toolId);
        const tool = toolId ? getTool(toolId) : null;
        if (!toolId || !tool?.defaultSize) return [];
        const geometry = clampGeometry(saved, viewport, {
          width: tool.defaultSize.minWidth,
          height: tool.defaultSize.minHeight,
        });
        return [{
          ...geometry,
          id: saved.id || crypto.randomUUID(),
          toolId,
          title: tool.title,
          minWidth: tool.defaultSize.minWidth,
          minHeight: tool.defaultSize.minHeight,
          zIndex: saved.zIndex,
          isMinimized: saved.isMinimized,
          isMaximized: saved.isMaximized,
          restoreGeometry: saved.restoreGeometry,
        }];
      });
      this.activeWindowId = this.windows.some((item) => item.id === workspace.desktop.activeWindowId)
        ? workspace.desktop.activeWindowId : null;
    }
    document.documentElement.setAttribute('data-theme', this.theme);
    this.ready = true;
  }

  openFloatingWindow(toolId: ToolId | string) {
    const windowToolId = migrateWindowToolId(toolId);
    const tool = windowToolId ? getTool(windowToolId) : null;
    if (!windowToolId || !tool?.defaultSize) return;
    const existing = this.windows.find((window) => window.toolId === windowToolId);
    if (existing) {
      this.restoreWindow(existing.id);
      return;
    }

    const viewport = this.viewport();
    const offset = (this.windows.length % 8) * 28;
    const geometry = clampGeometry({
      x: 110 + offset,
      y: 60 + offset,
      width: tool.defaultSize.width,
      height: tool.defaultSize.height,
    }, viewport, { width: tool.defaultSize.minWidth, height: tool.defaultSize.minHeight });
    const id = crypto.randomUUID();
    this.windows.push({
      ...geometry, id, toolId: windowToolId, title: tool.title,
      minWidth: tool.defaultSize.minWidth, minHeight: tool.defaultSize.minHeight,
      isMinimized: false, isMaximized: false, restoreGeometry: null,
      zIndex: Math.max(9, ...this.windows.map((window) => window.zIndex)) + 1,
    });
    this.focusWindow(id);
  }

  closeWindow(id: string) {
    this.windows = this.windows.filter((window) => window.id !== id);
    if (this.activeWindowId === id) this.activeWindowId = null;
    this.schedulePersist();
  }

  focusWindow(id: string) {
    const window = this.windows.find((item) => item.id === id);
    if (!window) return;
    window.isMinimized = false;
    window.zIndex = Math.max(9, ...this.windows.map((item) => item.zIndex)) + 1;
    this.activeWindowId = id;
    this.schedulePersist();
  }

  minimizeWindow(id: string) {
    const window = this.windows.find((item) => item.id === id);
    if (!window) return;
    window.isMinimized = true;
    if (this.activeWindowId === id) this.activeWindowId = null;
    this.schedulePersist();
  }

  restoreWindow(id: string) {
    this.focusWindow(id);
  }

  updateWindowGeometry(id: string, geometry: WindowGeometry) {
    const window = this.windows.find((item) => item.id === id);
    if (!window || window.isMaximized) return;
    Object.assign(window, clampGeometry(geometry, this.viewport(), {
      width: window.minWidth, height: window.minHeight,
    }));
    this.schedulePersist();
  }

  reconcileWindowBounds() {
    const viewport = this.viewport();
    for (const window of this.windows) {
      if (window.isMaximized) {
        Object.assign(window, { x: 0, y: 0, width: viewport.width, height: viewport.height });
      } else {
        Object.assign(window, clampGeometry(window, viewport, {
          width: window.minWidth, height: window.minHeight,
        }));
      }
    }
    this.schedulePersist();
  }

  toggleWindowMaximize(id: string) {
    const window = this.windows.find((item) => item.id === id);
    if (!window) return;
    if (window.isMaximized && window.restoreGeometry) {
      Object.assign(window, clampGeometry(window.restoreGeometry, this.viewport(), {
        width: window.minWidth, height: window.minHeight,
      }));
      window.restoreGeometry = null;
      window.isMaximized = false;
    } else {
      window.restoreGeometry = { x: window.x, y: window.y, width: window.width, height: window.height };
      const viewport = this.viewport();
      Object.assign(window, { x: 0, y: 0, width: viewport.width, height: viewport.height });
      window.isMaximized = true;
    }
    this.focusWindow(id);
  }

  addTodo(text: string) {
    const value = text.trim();
    if (!value || this.todos.length >= 500) return;
    this.todos.push({ id: crypto.randomUUID(), text: value, done: false });
    this.schedulePersist();
  }

  toggleTodo(id: string) {
    const todo = this.todos.find((item) => item.id === id);
    if (todo) todo.done = !todo.done;
    this.schedulePersist();
  }

  deleteTodo(id: string) {
    this.todos = this.todos.filter((todo) => todo.id !== id);
    this.schedulePersist();
  }

  setAppearance(values: { bgImageUrl?: string; bgBlur?: number }) {
    if (values.bgImageUrl !== undefined) this.bgImageUrl = values.bgImageUrl;
    if (values.bgBlur !== undefined) this.bgBlur = Math.min(100, Math.max(0, values.bgBlur));
    this.schedulePersist();
  }

  toggleTheme() {
    this.theme = this.theme === 'dark' ? 'light' : 'dark';
    document.documentElement.setAttribute('data-theme', this.theme);
    this.schedulePersist();
  }

  markTimersChanged() { this.schedulePersist(); }

  schedulePersist() {
    if (!this.ready) return;
    if (this.persistTimer !== null) window.clearTimeout(this.persistTimer);
    this.persistTimer = window.setTimeout(() => void this.persist(), 250);
  }

  persist() {
    if (!this.ready) return this.persistQueue;
    if (this.persistTimer !== null) {
      window.clearTimeout(this.persistTimer);
      this.persistTimer = null;
    }
    const snapshot = this.snapshot();
    this.persistQueue = this.persistQueue
      .catch(() => undefined)
      .then(() => saveWorkspace(snapshot))
      .catch((error) => console.error('Failed to persist workspace', error));
    return this.persistQueue;
  }

  addActivity(entry: Omit<ActivityEntry, 'meta'>) {
    this.recentActivity = [{ ...entry, meta: formatMeta() }, ...this.recentActivity].slice(0, 4);
  }

  pulseTool(id: ToolId) {
    this.activeToolPulse = id;
    window.setTimeout(() => { if (this.activeToolPulse === id) this.activeToolPulse = null; }, 900);
  }

  flashTimestampTile() {
    this.timestampFlash = true;
    this.pulseTool('timestamp');
    window.setTimeout(() => { this.timestampFlash = false; }, 700);
  }

  flashJsonTile() {
    this.jsonFlash = true;
    this.pulseTool('json-format');
    window.setTimeout(() => { this.jsonFlash = false; }, 900);
  }

  private snapshot(): PersistedWorkspaceV1 {
    return {
      schemaVersion: WORKSPACE_SCHEMA_VERSION,
      savedAt: Date.now(),
      preferences: {
        theme: this.theme, bgImageUrl: this.bgImageUrl,
        bgBlur: this.bgBlur, sidebarCollapsed: this.sidebarCollapsed,
      },
      desktop: {
        activeNavIndex: this.activeNavIndex,
        activeWindowId: this.activeWindowId,
        windows: this.windows.map(({ minWidth: _minWidth, minHeight: _minHeight, title: _title, ...window }) => ({ ...window })),
      },
      todos: this.todos.map((todo) => ({ ...todo })),
      timers: JSON.parse(JSON.stringify(this.timers)),
    };
  }

  private viewport() {
    return {
      width: Math.max(480, typeof window === 'undefined' ? 1366 : window.innerWidth),
      height: Math.max(360, (typeof window === 'undefined' ? 860 : window.innerHeight) - 132),
    };
  }
}

export const appState = new AppState();
