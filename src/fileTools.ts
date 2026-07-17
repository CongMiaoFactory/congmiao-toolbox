import { invoke } from '@tauri-apps/api/core';
import { open } from '@tauri-apps/plugin-dialog';

export type RenameRule =
  | { type: 'prefix'; value: string }
  | { type: 'suffix'; value: string }
  | { type: 'replace'; find: string; replacement: string; caseSensitive: boolean }
  | { type: 'sequence'; start: number; step: number; padding: number; position: 'prefix' | 'suffix'; separator: string }
  | { type: 'case'; mode: 'upper' | 'lower' }
  | { type: 'modifiedDate'; format: 'YYYY-MM-DD' | 'YYYYMMDD'; position: 'prefix' | 'suffix'; separator: string };

export interface FilePlanEntry {
  sourcePath: string; targetPath: string; originalName: string; targetName: string;
  size: number; status: 'ready' | 'invalid' | 'unchanged'; reason?: string;
}

export interface FilePlan {
  planId: string; kind: 'rename' | 'organize'; createdAt: number; entries: FilePlanEntry[];
  readyCount: number; invalidCount: number;
}

export interface FileOperationRecord {
  id: string; kind: 'rename' | 'organize'; createdAt: number; undone: boolean;
  moves: Array<{ sourcePath: string; targetPath: string; size: number; modifiedMs: number }>;
}

export interface FileJobProgress {
  jobId: string; stage: 'sample' | 'fullHash'; processedFiles: number; totalFiles: number;
  processedBytes: number; totalBytes: number; errorCount: number;
}

export interface DuplicateGroup { hash: string; size: number; paths: string[]; reclaimableBytes: number }
export interface DuplicateScanComplete {
  jobId: string; cancelled: boolean; groups: DuplicateGroup[]; errors: string[];
  scannedFiles: number; reclaimableBytes: number;
}

export async function chooseDirectory(title: string) {
  const selected = await open({ directory: true, multiple: false, title });
  return typeof selected === 'string' ? selected : null;
}

export const formatBytes = (bytes: number) => {
  if (!Number.isFinite(bytes) || bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  const index = Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), units.length - 1);
  return `${(bytes / 1024 ** index).toFixed(index === 0 ? 0 : 1)} ${units[index]}`;
};

export const executePlan = (planId: string) => invoke<FileOperationRecord>('execute_file_plan', { planId });
export const listOperations = () => invoke<FileOperationRecord[]>('list_file_operations');
export const undoOperation = (operationId: string) => invoke<FileOperationRecord>('undo_file_operation', { operationId });
export const clearOperations = () => invoke<void>('clear_file_operation_history');
