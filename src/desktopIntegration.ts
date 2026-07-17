import {
  isPermissionGranted,
  requestPermission,
  sendNotification,
} from '@tauri-apps/plugin-notification';
import { register, unregisterAll } from '@tauri-apps/plugin-global-shortcut';
import { getCurrentWindow } from '@tauri-apps/api/window';

let permissionRequest: Promise<boolean> | null = null;

export async function ensureNotificationPermission() {
  if (await isPermissionGranted()) return true;
  permissionRequest ??= requestPermission()
    .then((permission) => permission === 'granted')
    .catch(() => false)
    .finally(() => { permissionRequest = null; });
  return permissionRequest;
}

export async function notifyDesktop(title: string, body: string) {
  try {
    if (!await ensureNotificationPermission()) return false;
    sendNotification({ title, body });
    return true;
  } catch (error) {
    console.error('Failed to send desktop notification', error);
    return false;
  }
}

export const GLOBAL_SHORTCUT_OPTIONS = [
  'Ctrl+Alt+Space',
  'Ctrl+Shift+Space',
  'Ctrl+Alt+K',
  'Alt+Shift+Space',
] as const;

export function isSupportedGlobalShortcut(value: string) {
  return GLOBAL_SHORTCUT_OPTIONS.includes(value as typeof GLOBAL_SHORTCUT_OPTIONS[number]);
}

export async function configureGlobalShortcut(shortcut: string) {
  if (!isSupportedGlobalShortcut(shortcut)) throw new Error('不支持的全局快捷键');
  await unregisterAll();
  await register(shortcut, (event) => {
    if (event.state !== 'Pressed') return;
    void (async () => {
      const appWindow = getCurrentWindow();
      await appWindow.show();
      await appWindow.unminimize();
      await appWindow.setFocus();
      window.dispatchEvent(new CustomEvent('congmiao:open-palette'));
    })();
  });
}
