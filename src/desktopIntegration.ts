import {
  isPermissionGranted,
  requestPermission,
  sendNotification,
} from '@tauri-apps/plugin-notification';

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
