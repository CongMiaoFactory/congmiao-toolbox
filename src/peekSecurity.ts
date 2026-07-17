export function peekQrPayload(serverUrl: string) {
  const url = new URL(serverUrl);
  return `${url.protocol}//${url.host}`;
}

export function normalizeRefreshInterval(value: number) {
  return [0, 5, 10, 30].includes(value) ? value : 5;
}
