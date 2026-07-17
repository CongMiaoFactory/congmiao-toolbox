import { describe, expect, it } from 'vitest';
import { normalizeRefreshInterval, peekQrPayload } from './peekSecurity';

describe('Peek PC client security helpers', () => {
  it('keeps secrets out of the QR payload', () => {
    expect(peekQrPayload('http://192.168.1.8:3000/?code=123456#token=secret'))
      .toBe('http://192.168.1.8:3000');
  });
  it('normalizes the refresh policy', () => {
    expect(normalizeRefreshInterval(7)).toBe(5);
    expect(normalizeRefreshInterval(30)).toBe(30);
  });
});
