import type { WindowToolId } from './toolRegistry';

export const WORKSPACE_SCHEMA_VERSION = 1 as const;
export const DEFAULT_WALLPAPER = 'https://images.unsplash.com/photo-1558591710-4b4a1ae0f04d?q=80&w=2574&auto=format&fit=crop';

export interface TodoItem {
  id: string;
  text: string;
  done: boolean;
}

export interface WindowGeometry {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface PersistedWindow extends WindowGeometry {
  id: string;
  toolId: WindowToolId;
  zIndex: number;
  isMinimized: boolean;
  isMaximized: boolean;
  restoreGeometry: WindowGeometry | null;
}

export interface StopwatchSnapshot {
  elapsedMs: number;
  running: boolean;
  startedAt: number | null;
  laps: number[];
}

export interface CountdownSnapshot {
  inputMinutes: number;
  totalMs: number;
  remainingMs: number;
  running: boolean;
  targetAt: number | null;
}

export interface PomodoroSnapshot {
  mode: 'work' | 'break';
  workSeconds: number;
  breakSeconds: number;
  remainingSeconds: number;
  running: boolean;
  targetAt: number | null;
}

export interface TimerSnapshot {
  selectedMode: 'stopwatch' | 'countdown';
  stopwatch: StopwatchSnapshot;
  countdown: CountdownSnapshot;
  pomodoro: PomodoroSnapshot;
}

export interface PersistedWorkspaceV1 {
  schemaVersion: typeof WORKSPACE_SCHEMA_VERSION;
  savedAt: number;
  preferences: {
    theme: 'dark' | 'light';
    bgImageUrl: string;
    bgBlur: number;
    sidebarCollapsed: boolean;
  };
  desktop: {
    activeNavIndex: number;
    activeWindowId: string | null;
    windows: PersistedWindow[];
  };
  todos: TodoItem[];
  timers: TimerSnapshot;
}

export function defaultTimerSnapshot(): TimerSnapshot {
  return {
    selectedMode: 'stopwatch',
    stopwatch: { elapsedMs: 0, running: false, startedAt: null, laps: [] },
    countdown: { inputMinutes: 5, totalMs: 300_000, remainingMs: 300_000, running: false, targetAt: null },
    pomodoro: { mode: 'work', workSeconds: 1500, breakSeconds: 300, remainingSeconds: 1500, running: false, targetAt: null },
  };
}

export function clampGeometry(
  geometry: WindowGeometry,
  viewport: { width: number; height: number },
  minimum: { width: number; height: number },
): WindowGeometry {
  const width = Math.min(Math.max(geometry.width, minimum.width), Math.max(minimum.width, viewport.width));
  const height = Math.min(Math.max(geometry.height, minimum.height), Math.max(minimum.height, viewport.height));
  return {
    x: Math.min(Math.max(geometry.x, 0), Math.max(0, viewport.width - width)),
    y: Math.min(Math.max(geometry.y, 0), Math.max(0, viewport.height - height)),
    width,
    height,
  };
}

export function reconcileTimers(snapshot: TimerSnapshot, now = Date.now()): TimerSnapshot {
  const defaults = defaultTimerSnapshot();
  const timers: TimerSnapshot = {
    selectedMode: snapshot.selectedMode === 'countdown' ? 'countdown' : 'stopwatch',
    stopwatch: { ...defaults.stopwatch, ...snapshot.stopwatch },
    countdown: { ...defaults.countdown, ...snapshot.countdown },
    pomodoro: { ...defaults.pomodoro, ...snapshot.pomodoro },
  };
  const stopwatch = timers.stopwatch;
  stopwatch.elapsedMs = Math.max(0, Number(stopwatch.elapsedMs) || 0);
  stopwatch.laps = Array.isArray(stopwatch.laps)
    ? stopwatch.laps.filter((lap) => Number.isFinite(lap) && lap >= 0).slice(0, 100)
    : [];
  if (stopwatch.running && stopwatch.startedAt !== null && stopwatch.startedAt > now) {
    stopwatch.startedAt = now;
  }

  const countdown = timers.countdown;
  countdown.inputMinutes = Math.min(1440, Math.max(1, Number(countdown.inputMinutes) || 5));
  countdown.totalMs = Math.max(0, Number(countdown.totalMs) || countdown.inputMinutes * 60_000);
  countdown.remainingMs = Math.max(0, Number(countdown.remainingMs) || 0);
  if (countdown.running && countdown.targetAt !== null) {
    countdown.remainingMs = Math.max(0, countdown.targetAt - now);
    if (countdown.remainingMs === 0) {
      countdown.running = false;
      countdown.targetAt = null;
    }
  }

  const pomodoro = timers.pomodoro;
  pomodoro.mode = pomodoro.mode === 'break' ? 'break' : 'work';
  pomodoro.workSeconds = Math.max(60, Number(pomodoro.workSeconds) || 1500);
  pomodoro.breakSeconds = Math.max(60, Number(pomodoro.breakSeconds) || 300);
  pomodoro.remainingSeconds = Math.max(0, Number(pomodoro.remainingSeconds) || 0);
  if (pomodoro.running && pomodoro.targetAt !== null) {
    let target = pomodoro.targetAt;
    let mode = pomodoro.mode;
    while (target <= now) {
      mode = mode === 'work' ? 'break' : 'work';
      target += (mode === 'work' ? pomodoro.workSeconds : pomodoro.breakSeconds) * 1000;
    }
    pomodoro.mode = mode;
    pomodoro.targetAt = target;
    pomodoro.remainingSeconds = Math.max(0, Math.ceil((target - now) / 1000));
  }
  return timers;
}

export function isWorkspaceV1(value: unknown): value is PersistedWorkspaceV1 {
  if (!value || typeof value !== 'object') return false;
  const candidate = value as Partial<PersistedWorkspaceV1>;
  const preferences = candidate.preferences as Record<string, unknown> | undefined;
  const desktop = candidate.desktop as Record<string, unknown> | undefined;
  const timers = candidate.timers as Record<string, unknown> | undefined;
  return candidate.schemaVersion === WORKSPACE_SCHEMA_VERSION
    && !!preferences
    && (preferences.theme === 'dark' || preferences.theme === 'light')
    && typeof preferences.bgImageUrl === 'string'
    && typeof preferences.bgBlur === 'number'
    && typeof preferences.sidebarCollapsed === 'boolean'
    && !!desktop
    && typeof desktop.activeNavIndex === 'number'
    && Array.isArray(desktop.windows)
    && Array.isArray(candidate.todos)
    && !!timers
    && typeof timers.stopwatch === 'object'
    && typeof timers.countdown === 'object'
    && typeof timers.pomodoro === 'object';
}
