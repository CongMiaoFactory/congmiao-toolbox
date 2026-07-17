export type ToastLevel = 'success' | 'error' | 'info';
export interface ToastMessage { id: string; level: ToastLevel; message: string; duration: number }

class ToastState {
  messages = $state<ToastMessage[]>([]);
  show(message: string, level: ToastLevel = 'info', duration = level === 'error' ? 6000 : 3500) {
    const value = message.trim(); if (!value) return '';
    const id = crypto.randomUUID();
    this.messages = [...this.messages, { id, level, message: value, duration }].slice(-4);
    window.setTimeout(() => this.dismiss(id), duration);
    return id;
  }
  dismiss(id: string) { this.messages = this.messages.filter((item) => item.id !== id); }
  clear() { this.messages = []; }
}

export const toastState = new ToastState();
export const toast = {
  success: (message: string, duration?: number) => toastState.show(message, 'success', duration),
  error: (message: string, duration?: number) => toastState.show(message, 'error', duration),
  info: (message: string, duration?: number) => toastState.show(message, 'info', duration),
};

export function errorMessage(error: unknown, fallback = '操作失败') {
  if (typeof error === 'string' && error.trim()) return error;
  if (error instanceof Error && error.message.trim()) return error.message;
  return fallback;
}
