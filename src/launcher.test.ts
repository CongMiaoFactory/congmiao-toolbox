import { describe, expect, it } from 'vitest';
import { buildLauncherResults, calculate, fuzzyScore } from './launcher';
import { toolRegistry } from './toolRegistry';

describe('quick launcher', () => {
  it('scores fuzzy matches and boosts favorites', () => {
    expect(fuzzyScore('json', 'json 格式化')).toBeGreaterThan(0);
    const results = buildLauncherResults('', toolRegistry, [], ['timer'], []);
    expect(results[0].toolId).toBe('timer');
  });

  it('parses safe calculations without eval', () => {
    expect(calculate('=(2 + 3) * 4')).toBe(20);
    expect(calculate('2 ** 8')).toBeNull();
    expect(calculate('alert(1)')).toBeNull();
  });

  it('creates timer, todo and URL actions', () => {
    expect(buildLauncherResults('> timer 10m', toolRegistry, [], [], [])[0]).toMatchObject({ kind: 'timer', seconds: 600 });
    expect(buildLauncherResults('> todo 提交项目', toolRegistry, [], [], [])[0]).toMatchObject({ kind: 'todo', value: '提交项目' });
    expect(buildLauncherResults('example.com', toolRegistry, [], [], [])[0]).toMatchObject({ kind: 'url' });
  });
});
