import { describe, expect, it, vi } from 'vitest';

vi.mock('@tauri-apps/api/core', () => ({ invoke: vi.fn() }));
vi.mock('@tauri-apps/plugin-dialog', () => ({ open: vi.fn() }));

import { formatBytes } from './fileTools';
import { getTool } from './toolRegistry';

describe('safe file tools', () => {
  it('formats scan and plan sizes consistently', () => {
    expect(formatBytes(0)).toBe('0 B');
    expect(formatBytes(1536)).toBe('1.5 KB');
    expect(formatBytes(10 * 1024 ** 2)).toBe('10.0 MB');
  });

  it('publishes all file tools as real windows', () => {
    expect(['batch-rename', 'sort-rule', 'duplicate-scan'].map((id) => getTool(id)?.kind))
      .toEqual(['window', 'window', 'window']);
  });
});
