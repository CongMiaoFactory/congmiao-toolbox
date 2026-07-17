import type { Component } from 'svelte';
import type { WindowToolId } from './toolRegistry';

export type WindowComponentModule = { default: Component };
export type WindowComponentLoader = () => Promise<WindowComponentModule>;

// Keep every tool behind a dynamic import so opening the desktop does not also
// initialize large editors, file scanners, QR generation, or Ruff WASM.
export const windowComponentLoaders: Record<WindowToolId, WindowComponentLoader> = {
  json: () => import('./components/JsonFormatter.svelte'),
  python: () => import('./components/PythonFormatter.svelte'),
  encoder: () => import('./components/EncoderTool.svelte'),
  color: () => import('./components/ColorPickerTool.svelte'),
  hash: () => import('./components/HashTool.svelte'),
  image: () => import('./components/ImageConverterTool.svelte'),
  timer: () => import('./components/TimerTool.svelte'),
  translator: () => import('./components/TranslatorTool.svelte'),
  peek_pc: () => import('./components/PeekPCTool.svelte'),
  'lucky-wheel': () => import('./components/LuckyWheelTool.svelte'),
  'batch-rename': () => import('./components/BatchRenameTool.svelte'),
  'sort-rule': () => import('./components/FileOrganizerTool.svelte'),
  'duplicate-scan': () => import('./components/DuplicateScannerTool.svelte'),
};

const componentCache = new Map<WindowToolId, Promise<WindowComponentModule>>();

export function loadWindowComponent(toolId: WindowToolId) {
  const cached = componentCache.get(toolId);
  if (cached) return cached;
  const pending = windowComponentLoaders[toolId]();
  componentCache.set(toolId, pending);
  return pending;
}
