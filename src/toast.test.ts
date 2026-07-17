import { beforeEach, describe, expect, it, vi } from 'vitest';
import { toastState } from './toast.svelte';

describe('toast queue', () => {
  beforeEach(() => { vi.useFakeTimers(); toastState.clear(); });
  it('keeps at most four messages and expires them', () => {
    for (let i = 0; i < 5; i += 1) toastState.show(`message ${i}`, 'info', 1000);
    expect(toastState.messages).toHaveLength(4);
    vi.advanceTimersByTime(1000);
    expect(toastState.messages).toHaveLength(0);
  });
});
