import { invoke } from '@tauri-apps/api/core';
import { load, type Store } from '@tauri-apps/plugin-store';
import { isWorkspaceV1, type PersistedWorkspaceV1 } from './workspace';

const STORE_FILE = 'workspace.json';
const STORE_KEY = 'workspace';
let storePromise: Promise<Store> | null = null;

async function openStore() {
  if (!storePromise) storePromise = load(STORE_FILE, { autoSave: false, defaults: {} });
  return storePromise;
}

export async function loadWorkspace(): Promise<PersistedWorkspaceV1 | null> {
  try {
    const store = await openStore();
    const value = await store.get<unknown>(STORE_KEY);
    if (value === null || value === undefined) return null;
    if (isWorkspaceV1(value)) return value;
    await store.set(`workspace.invalid.${Date.now()}`, value);
    await store.delete(STORE_KEY);
    await store.save();
    return null;
  } catch (error) {
    console.error('Failed to load workspace store', error);
    try {
      await invoke('recover_workspace_store');
      storePromise = null;
      await openStore();
    } catch (recoveryError) {
      console.error('Failed to recover workspace store', recoveryError);
    }
    return null;
  }
}

export async function saveWorkspace(workspace: PersistedWorkspaceV1) {
  const store = await openStore();
  await store.set(STORE_KEY, workspace);
  await store.save();
}

const MAX_WALLPAPER_BYTES = 15 * 1024 * 1024;
const MAX_WALLPAPER_DIMENSION = 2560;

export async function encodeWallpaper(file: File): Promise<string> {
  if (!file.type.startsWith('image/')) throw new Error('请选择图片文件');
  if (file.size > MAX_WALLPAPER_BYTES) throw new Error('图片不能超过 15 MB');

  const source = await fileToDataUrl(file);
  const image = await loadImage(source);
  const ratio = Math.min(1, MAX_WALLPAPER_DIMENSION / Math.max(image.naturalWidth, image.naturalHeight));
  const canvas = document.createElement('canvas');
  canvas.width = Math.max(1, Math.round(image.naturalWidth * ratio));
  canvas.height = Math.max(1, Math.round(image.naturalHeight * ratio));
  const context = canvas.getContext('2d');
  if (!context) throw new Error('当前环境无法处理图片');
  context.drawImage(image, 0, 0, canvas.width, canvas.height);
  return canvas.toDataURL('image/webp', 0.88);
}

function fileToDataUrl(file: File) {
  return new Promise<string>((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result));
    reader.onerror = () => reject(new Error('读取图片失败'));
    reader.readAsDataURL(file);
  });
}

function loadImage(source: string) {
  return new Promise<HTMLImageElement>((resolve, reject) => {
    const image = new Image();
    image.onload = () => resolve(image);
    image.onerror = () => reject(new Error('图片解码失败'));
    image.src = source;
  });
}
