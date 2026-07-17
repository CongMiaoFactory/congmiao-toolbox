export function peekQrPayload(serverUrl: string) {
  const url = new URL(serverUrl);
  return `${url.protocol}//${url.host}`;
}

export function pairingRemainingSeconds(expiresAt: number | null, now = Date.now()) {
  return expiresAt ? Math.max(0, Math.ceil((expiresAt - now) / 1000)) : 0;
}

export function normalizeRefreshInterval(value: number) {
  return [0, 5, 10, 30].includes(value) ? value : 5;
}
