import { describe, expect, it } from 'vitest';
import { migrateWindowToolId, toolRegistry, windowTools } from './toolRegistry';
import { windowComponentLoaders } from './windowComponents';
import { clampGeometry, defaultTimerSnapshot, isWorkspaceV1, reconcileTimers, timerPreset } from './workspace';

describe('workspace geometry', () => {
  it('clamps restored windows into the visible desktop', () => {
    expect(clampGeometry(
      { x: 1800, y: -100, width: 1200, height: 900 },
      { width: 1000, height: 700 },
      { width: 500, height: 400 },
    )).toEqual({ x: 0, y: 0, width: 1000, height: 700 });
  });
});

describe('timer recovery', () => {
  it('finishes an expired countdown', () => {
    const timers = defaultTimerSnapshot();
    timers.countdown.running = true;
    timers.countdown.targetAt = 9_000;
    const restored = reconcileTimers(timers, 10_000);
    expect(restored.countdown).toMatchObject({ running: false, remainingMs: 0, targetAt: null });
  });

  it('advances pomodoro cycles using real elapsed time', () => {
    const timers = defaultTimerSnapshot();
    timers.pomodoro = {
      mode: 'work', workSeconds: 60, breakSeconds: 60,
      remainingSeconds: 1, running: true, targetAt: 1_000,
    };
    const restored = reconcileTimers(timers, 70_000);
    expect(restored.pomodoro.mode).toBe('work');
    expect(restored.pomodoro.targetAt).toBe(121_000);
  });

  it('stores timer presets without live targets', () => {
    const timers = defaultTimerSnapshot();
    timers.countdown.running = true;
    timers.countdown.targetAt = 12345;
    timers.pomodoro.running = true;
    timers.pomodoro.targetAt = 67890;
    const preset = timerPreset(timers);
    expect(preset.countdown).toMatchObject({ running: false, targetAt: null });
    expect(preset.pomodoro).toMatchObject({ running: false, targetAt: null });
  });
});

describe('workspace schema and tool registry', () => {
  it('rejects malformed workspace data', () => {
    expect(isWorkspaceV1({ schemaVersion: 1 })).toBe(false);
  });

  it('migrates legacy floating-window aliases', () => {
    expect(migrateWindowToolId('json-format')).toBe('json');
    expect(migrateWindowToolId('hash-check')).toBe('hash');
    expect(migrateWindowToolId('timestamp')).toBe('timer');
  });

  it('contains unique tool IDs and a component for every window tool', () => {
    const ids = toolRegistry.map((tool) => tool.id);
    expect(new Set(ids).size).toBe(ids.length);
    expect(Object.keys(windowComponentLoaders).sort()).toEqual(windowTools.map((tool) => tool.id).sort());
  });
});
