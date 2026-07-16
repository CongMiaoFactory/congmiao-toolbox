import { appState, type ToolId } from './state.svelte';

export async function copyText(text: string) {
  try {
    await navigator.clipboard.writeText(text);
    return true;
  } catch {
    try {
      const helper = document.createElement('textarea');
      helper.value = text;
      helper.style.position = 'fixed';
      helper.style.opacity = '0';
      document.body.append(helper);
      helper.select();
      document.execCommand('copy');
      helper.remove();
      return true;
    } catch {
      return false;
    }
  }
}

export async function readClipboardText() {
  try {
    return await navigator.clipboard.readText();
  } catch {
    return '';
  }
}

export async function runTimestampFromClock() {
  const payload = `${appState.currentUnix}`;
  const copied = await copyText(payload);

  appState.addActivity({
    source: 'TEXT',
    title: 'Timestamp Copied',
    value: copied ? payload : '复制失败',
    accent: 'teal',
  });

  appState.flashTimestampTile();
}

export function formatDateTime(value: number) {
  const date = new Date(value);
  const year = date.getFullYear();
  const month = `${date.getMonth() + 1}`.padStart(2, '0');
  const day = `${date.getDate()}`.padStart(2, '0');
  const hour = `${date.getHours()}`.padStart(2, '0');
  const minute = `${date.getMinutes()}`.padStart(2, '0');
  const second = `${date.getSeconds()}`.padStart(2, '0');
  return `${year}-${month}-${day} ${hour}:${minute}:${second}`;
}

export async function runTimestampFromDrop(file: File) {
  const unix = Math.floor(file.lastModified / 1000);
  const formatted = formatDateTime(file.lastModified);
  const payload = `${file.name}\n${unix}\n${formatted}`;
  const copied = await copyText(payload);

  appState.addActivity({
    source: 'FILE',
    title: 'Timestamp Convert',
    value: copied ? `${file.name} -> ${unix}` : `${file.name} 复制失败`,
    accent: 'blue',
  });

  appState.flashTimestampTile();
}

export function previewJson(value: unknown) {
  if (Array.isArray(value)) {
    return `[${value.length} items]`;
  }

  if (value && typeof value === 'object') {
    return Object.keys(value as Record<string, unknown>)
      .slice(0, 4)
      .join(', ');
  }

  return String(value);
}

export async function runJsonFormat() {
  const text = await readClipboardText();
  if (!text) {
    appState.addActivity({
      source: 'TEXT',
      title: 'JSON Format',
      value: '剪贴板为空',
      accent: 'teal',
    });
    return;
  }

  try {
    const parsed = JSON.parse(text);
    const pretty = JSON.stringify(parsed, null, 2);
    const copied = await copyText(pretty);

    appState.clipboardJsonReady = true;
    appState.clipboardJsonHint = copied ? '已格式化' : '复制失败';
    appState.clipboardJsonPreview = previewJson(parsed);

    appState.addActivity({
      source: 'TEXT',
      title: 'JSON Format',
      value: copied ? `${pretty.length} chars copied` : '格式化完成',
      accent: 'teal',
    });

    appState.flashJsonTile();
  } catch {
    appState.clipboardJsonReady = false;
    appState.clipboardJsonHint = '剪贴板内容不是 JSON';

    appState.addActivity({
      source: 'TEXT',
      title: 'JSON Format',
      value: '不是合法 JSON',
      accent: 'teal',
    });
  }
}

export async function runUrlEncode() {
  const text = await readClipboardText();
  if (!text) {
    appState.addActivity({
      source: 'TEXT',
      title: 'URL Encode',
      value: '剪贴板为空',
      accent: 'teal',
    });
    return;
  }

  const encoded = encodeURIComponent(text);
  const copied = await copyText(encoded);

  appState.addActivity({
    source: 'TEXT',
    title: 'URL Encode',
    value: copied ? '结果已复制' : '编码完成',
    accent: 'teal',
  });

  appState.pulseTool('url-encode');
}

export async function runBase64() {
  const text = await readClipboardText();
  if (!text) {
    appState.addActivity({
      source: 'TEXT',
      title: 'Base64',
      value: '剪贴板为空',
      accent: 'teal',
    });
    return;
  }

  const bytes = new TextEncoder().encode(text);
  let binary = '';
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }

  const encoded = btoa(binary);
  const copied = await copyText(encoded);

  appState.addActivity({
    source: 'TEXT',
    title: 'Base64',
    value: copied ? '结果已复制' : '编码完成',
    accent: 'teal',
  });

  appState.pulseTool('base64');
}

export async function runHashCheck() {
  const text = await readClipboardText();
  if (!text) {
    appState.addActivity({
      source: 'FILE',
      title: 'Hash Check',
      value: '剪贴板为空',
      accent: 'blue',
    });
    return;
  }

  const buffer = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
  const hash = Array.from(new Uint8Array(buffer))
    .map((value) => value.toString(16).padStart(2, '0'))
    .join('');

  const copied = await copyText(hash);

  appState.addActivity({
    source: 'FILE',
    title: 'Hash Check',
    value: copied ? `${hash.slice(0, 12)}... copied` : hash.slice(0, 18),
    accent: 'blue',
  });

  appState.pulseTool('hash-check');
}

export function runComingSoon(id: ToolId, title: string) {
  appState.addActivity({
    source: 'FILE',
    title,
    value: '入口已预留，后续接本地逻辑',
    accent: 'blue',
  });

  appState.pulseTool(id);
}

export async function runTool(id: ToolId) {
  switch (id) {
    case 'timestamp':
      await runTimestampFromClock();
      break;
    case 'json-format':
      await runJsonFormat();
      break;
    case 'url-encode':
      await runUrlEncode();
      break;
    case 'base64':
      await runBase64();
      break;
    case 'hash-check':
      await runHashCheck();
      break;
    case 'batch-rename':
      runComingSoon(id, 'Batch Rename');
      break;
    case 'sort-rule':
      runComingSoon(id, 'Sort by Rule');
      break;
    case 'duplicate-scan':
      runComingSoon(id, 'Duplicate Scan');
      break;
    case 'lucky-wheel':
      appState.openFloatingWindow('lucky-wheel');
      appState.activeNavIndex = 0;
      appState.addActivity({
        source: 'TEXT',
        title: 'Lucky Wheel',
        value: '已打开幸运大转盘',
        accent: 'blue',
      });
      break;
  }
}

export async function inspectClipboardJson() {
  if (!document.hasFocus()) {
    return;
  }

  const text = await readClipboardText();
  if (!text) {
    appState.clipboardJsonReady = false;
    appState.clipboardJsonHint = '剪贴板为空';
    appState.clipboardJsonPreview = '{ ... }';
    return;
  }

  try {
    const parsed = JSON.parse(text);
    appState.clipboardJsonReady = true;
    appState.clipboardJsonHint = '检测到剪贴板 JSON';
    appState.clipboardJsonPreview = previewJson(parsed);
  } catch {
    appState.clipboardJsonReady = false;
    appState.clipboardJsonHint = '剪贴板暂未检测到 JSON';
    appState.clipboardJsonPreview = '{ ... }';
  }
}
