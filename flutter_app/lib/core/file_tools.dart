import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'ids.dart';

/// Dart port of `src-tauri/src/file_tools.rs`: safe batch rename, rule-based
/// organizing and duplicate scanning with the same invariants —
/// preview-before-execute, source verification, two-phase renames that
/// support swaps, cross-device safe moves, an atomic undo journal and a
/// staged (sample → full) hash pipeline.
///
/// Pure `dart:io` + `crypto`, no Flutter imports, so everything here is
/// covered by plain unit tests against temp directories.
const planTtl = Duration(minutes: 10);
const journalLimit = 10;
const sampleSize = 64 * 1024;

class FileToolException implements Exception {
  const FileToolException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _CancelledException implements Exception {
  const _CancelledException();
}

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

sealed class RenameRule {
  const RenameRule();
}

class PrefixRule extends RenameRule {
  const PrefixRule(this.value);

  final String value;
}

class SuffixRule extends RenameRule {
  const SuffixRule(this.value);

  final String value;
}

class ReplaceRule extends RenameRule {
  const ReplaceRule({
    required this.find,
    required this.replacement,
    required this.caseSensitive,
  });

  final String find;
  final String replacement;
  final bool caseSensitive;
}

class SequenceRule extends RenameRule {
  const SequenceRule({
    required this.start,
    required this.step,
    required this.padding,
    required this.position,
    required this.separator,
  });

  final int start;
  final int step;
  final int padding;
  final String position; // prefix | suffix
  final String separator;
}

class CaseRule extends RenameRule {
  const CaseRule(this.mode); // upper | lower

  final String mode;
}

class ModifiedDateRule extends RenameRule {
  const ModifiedDateRule({
    required this.format, // YYYY-MM-DD | YYYYMMDD
    required this.position,
    required this.separator,
  });

  final String format;
  final String position;
  final String separator;
}

class FilePlanEntry {
  FilePlanEntry({
    required this.sourcePath,
    required this.targetPath,
    required this.originalName,
    required this.targetName,
    required this.size,
    required this.status, // ready | invalid | unchanged
    this.reason,
  });

  final String sourcePath;
  final String targetPath;
  final String originalName;
  final String targetName;
  final int size;
  final String status;
  final String? reason;
}

class FilePlan {
  FilePlan({
    required this.planId,
    required this.kind, // rename | organize
    required this.createdAt,
    required this.entries,
    required this.readyCount,
    required this.invalidCount,
  });

  final String planId;
  final String kind;
  final int createdAt;
  final List<FilePlanEntry> entries;
  final int readyCount;
  final int invalidCount;
}

class _StoredEntry {
  _StoredEntry({
    required this.entry,
    required this.size,
    required this.modifiedMs,
  });

  final FilePlanEntry entry;
  final int size;
  final int modifiedMs;
}

class _StoredPlan {
  _StoredPlan({required this.plan, required this.entries})
      : created = DateTime.now();

  final FilePlan plan;
  final List<_StoredEntry> entries;
  final DateTime created;
}

class OperationMove {
  OperationMove({
    required this.sourcePath,
    required this.targetPath,
    required this.size,
    required this.modifiedMs,
  });

  factory OperationMove.fromJson(Map<String, dynamic> json) => OperationMove(
        sourcePath: json['sourcePath'] as String? ?? '',
        targetPath: json['targetPath'] as String? ?? '',
        size: (json['size'] as num?)?.toInt() ?? 0,
        modifiedMs: (json['modifiedMs'] as num?)?.toInt() ?? 0,
      );

  final String sourcePath;
  final String targetPath;
  final int size;
  final int modifiedMs;

  Map<String, dynamic> toJson() => {
        'sourcePath': sourcePath,
        'targetPath': targetPath,
        'size': size,
        'modifiedMs': modifiedMs,
      };
}

class FileOperationRecord {
  FileOperationRecord({
    required this.id,
    required this.kind,
    required this.createdAt,
    required this.undone,
    required this.moves,
  });

  factory FileOperationRecord.fromJson(Map<String, dynamic> json) =>
      FileOperationRecord(
        id: json['id'] as String? ?? '',
        kind: json['kind'] as String? ?? 'rename',
        createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
        undone: json['undone'] as bool? ?? false,
        moves: json['moves'] is List
            ? (json['moves'] as List)
                .whereType<Map<String, dynamic>>()
                .map(OperationMove.fromJson)
                .toList()
            : <OperationMove>[],
      );

  final String id;
  final String kind;
  final int createdAt;
  bool undone;
  final List<OperationMove> moves;

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'createdAt': createdAt,
        'undone': undone,
        'moves': moves.map((move) => move.toJson()).toList(),
      };
}

sealed class OrganizeMode {
  const OrganizeMode();
}

class OrganizeByExtension extends OrganizeMode {
  const OrganizeByExtension();
}

class OrganizeByModifiedDate extends OrganizeMode {
  const OrganizeByModifiedDate(this.granularity); // year | month

  final String granularity;
}

class OrganizeBySize extends OrganizeMode {
  const OrganizeBySize({required this.smallBytes, required this.largeBytes});

  final int smallBytes;
  final int largeBytes;
}

class ExtensionMapping {
  const ExtensionMapping({required this.extension, required this.folder});

  final String extension;
  final String folder;
}

class FileJobProgress {
  const FileJobProgress({
    required this.jobId,
    required this.stage, // sample | fullHash
    required this.processedFiles,
    required this.totalFiles,
    required this.processedBytes,
    required this.totalBytes,
    required this.errorCount,
  });

  final String jobId;
  final String stage;
  final int processedFiles;
  final int totalFiles;
  final int processedBytes;
  final int totalBytes;
  final int errorCount;
}

class DuplicateGroup {
  const DuplicateGroup({
    required this.hash,
    required this.size,
    required this.paths,
    required this.reclaimableBytes,
  });

  final String hash;
  final int size;
  final List<String> paths;
  final int reclaimableBytes;
}

class DuplicateScanComplete {
  const DuplicateScanComplete({
    required this.jobId,
    required this.cancelled,
    required this.groups,
    required this.errors,
    required this.scannedFiles,
    required this.reclaimableBytes,
  });

  final String jobId;
  final bool cancelled;
  final List<DuplicateGroup> groups;
  final List<String> errors;
  final int scannedFiles;
  final int reclaimableBytes;
}

class DuplicateScanJob {
  DuplicateScanJob._(this.jobId, this._cancelled);

  final String jobId;
  final _CancelFlag _cancelled;
  late final Future<DuplicateScanComplete> done;

  void cancel() => _cancelled.value = true;
}

class _CancelFlag {
  bool value = false;
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

int _nowMs() => DateTime.now().millisecondsSinceEpoch;

int _modifiedMs(FileStat stat) => stat.modified.millisecondsSinceEpoch;

String pathKey(String path) =>
    Platform.isWindows || Platform.isMacOS ? path.toLowerCase() : path;

String canonicalDir(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw const FileToolException('无法访问目录：路径为空');
  }
  final type = FileSystemEntity.typeSync(trimmed);
  if (type == FileSystemEntityType.notFound) {
    throw FileToolException('无法访问目录：$trimmed');
  }
  if (type != FileSystemEntityType.directory) {
    throw const FileToolException('选择的路径不是目录');
  }
  try {
    return Directory(trimmed).resolveSymbolicLinksSync();
  } on FileSystemException catch (error) {
    throw FileToolException('无法访问目录：${error.message}');
  }
}

List<String> gatherFiles(
  String root, {
  required bool recursive,
  String? excluded,
  required List<String> errors,
}) {
  final output = <String>[];
  final dirs = <String>[root];
  while (dirs.isNotEmpty) {
    final dir = dirs.removeLast();
    final List<FileSystemEntity> entries;
    try {
      entries = Directory(dir).listSync(followLinks: false);
    } on FileSystemException catch (error) {
      errors.add('$dir: ${error.message}');
      continue;
    }
    for (final entity in entries) {
      if (entity is Link) continue;
      if (entity is File) {
        output.add(entity.path);
      } else if (entity is Directory && recursive) {
        final within = excluded != null &&
            (p.equals(excluded, entity.path) ||
                p.isWithin(excluded, entity.path));
        if (!within) dirs.add(entity.path);
      }
    }
  }
  output.sort((a, b) => pathKey(a).compareTo(pathKey(b)));
  return output;
}

(String, String) splitName(String path, {required bool includeExtension}) {
  final filename = p.basename(path);
  if (includeExtension) return (filename, '');
  return (p.basenameWithoutExtension(filename), p.extension(filename));
}

String replaceInsensitive(String input, String find, String replacement) {
  if (find.isEmpty) return input;
  final lower = input.toLowerCase();
  final needle = find.toLowerCase();
  // Mirror the Rust guard: bail out when lowercasing shifts offsets.
  if (lower.length != input.length) return input;
  final result = StringBuffer();
  var cursor = 0;
  while (true) {
    final offset = lower.indexOf(needle, cursor);
    if (offset == -1) break;
    result.write(input.substring(cursor, offset));
    result.write(replacement);
    cursor = offset + needle.length;
  }
  result.write(input.substring(cursor));
  return result.toString();
}

String _sequenceToken(int value, int padding) {
  final width = math.min(padding, 12);
  if (width <= 0) return value.toString();
  if (value < 0) {
    final digits = value.abs().toString();
    return '-${digits.padLeft(math.max(0, width - 1), '0')}';
  }
  return value.toString().padLeft(width, '0');
}

String _dateToken(DateTime date, String format) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return format == 'YYYYMMDD' ? '$y$m$d' : '$y-$m-$d';
}

String applyRules(
  String path,
  int index, {
  required bool includeExtension,
  required List<RenameRule> rules,
}) {
  final (baseName, extension) =
      splitName(path, includeExtension: includeExtension);
  var name = baseName;
  final FileStat stat = File(path).statSync();
  if (stat.type == FileSystemEntityType.notFound) {
    throw FileToolException('无法读取文件信息：$path');
  }
  for (final rule in rules) {
    switch (rule) {
      case PrefixRule(:final value):
        name = '$value$name';
      case SuffixRule(:final value):
        name = '$name$value';
      case ReplaceRule(:final find, :final replacement, :final caseSensitive):
        name = caseSensitive
            ? name.replaceAll(find, replacement)
            : replaceInsensitive(name, find, replacement);
      case SequenceRule(
          :final start,
          :final step,
          :final padding,
          :final position,
          :final separator
        ):
        final token = _sequenceToken(start + step * index, padding);
        name = position == 'prefix'
            ? '$token$separator$name'
            : '$name$separator$token';
      case CaseRule(:final mode):
        name = mode == 'upper' ? name.toUpperCase() : name.toLowerCase();
      case ModifiedDateRule(:final format, :final position, :final separator):
        final token = _dateToken(stat.modified, format);
        name = position == 'prefix'
            ? '$token$separator$name'
            : '$name$separator$token';
    }
  }
  return '$name$extension';
}

const _reservedNames = {
  'CON', 'PRN', 'AUX', 'NUL', //
  'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
  'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9',
};

String? filenameError(String name) {
  if (name.isEmpty || name == '.' || name == '..') {
    return '文件名不能为空';
  }
  const illegal = '<>:"/\\|?*';
  for (final unit in name.codeUnits) {
    if (unit < 0x20 || illegal.contains(String.fromCharCode(unit))) {
      return '文件名包含非法字符';
    }
  }
  if (name.endsWith(' ') || name.endsWith('.')) {
    return '文件名不能以空格或句点结尾';
  }
  final stem = name.split('.').first.toUpperCase();
  if (_reservedNames.contains(stem)) {
    return '文件名是系统保留名称';
  }
  return null;
}

String relativeFolder(String value) {
  final trimmed = value.trim();
  const message = '自定义文件夹必须是目标目录下的相对路径，且不能包含 . 或 ..';
  if (trimmed.isEmpty || p.isAbsolute(trimmed)) {
    throw const FileToolException(message);
  }
  final parts = p.split(trimmed);
  for (final part in parts) {
    if (part.isEmpty || part == '.' || part == '..' || part.contains(':')) {
      throw const FileToolException(message);
    }
  }
  return p.joinAll(parts);
}

void _ensureTargetIsNotSymlink(String root, String relative) {
  var current = root;
  for (final part in p.split(relative)) {
    current = p.join(current, part);
    if (FileSystemEntity.typeSync(current, followLinks: false) ==
        FileSystemEntityType.link) {
      throw FileToolException('目标路径包含符号链接：$current');
    }
  }
}

String extensionCategory(String ext) {
  switch (ext) {
    case 'jpg' || 'jpeg' || 'png' || 'gif' || 'webp' || 'bmp' || 'svg' || 'heic':
      return '图片';
    case 'mp4' || 'mkv' || 'mov' || 'avi' || 'webm' || 'flv':
      return '视频';
    case 'mp3' || 'wav' || 'flac' || 'aac' || 'ogg' || 'm4a':
      return '音频';
    case 'pdf' || 'doc' || 'docx' || 'xls' || 'xlsx' || 'ppt' || 'pptx' ||
          'txt' || 'md':
      return '文档';
    case 'zip' || '7z' || 'rar' || 'tar' || 'gz' || 'bz2':
      return '压缩包';
    case 'rs' || 'js' || 'ts' || 'tsx' || 'jsx' || 'py' || 'java' || 'c' ||
          'cpp' || 'h' || 'css' || 'html' || 'json' || 'toml' || 'yaml' ||
          'yml' || 'dart':
      return '代码';
    default:
      return '其他';
  }
}

String formatBytes(num bytes) {
  if (!bytes.isFinite || bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  final index = math.min(
      (math.log(bytes) / math.log(1024)).floor(), units.length - 1);
  final value = bytes / math.pow(1024, index);
  return '${value.toStringAsFixed(index == 0 ? 0 : 1)} ${units[index]}';
}

// ---------------------------------------------------------------------------
// Requests
// ---------------------------------------------------------------------------

class RenamePreviewRequest {
  const RenamePreviewRequest({
    required this.sourceDir,
    this.recursive = false,
    this.includeExtension = false,
    required this.rules,
  });

  final String sourceDir;
  final bool recursive;
  final bool includeExtension;
  final List<RenameRule> rules;
}

class OrganizePreviewRequest {
  const OrganizePreviewRequest({
    required this.sourceDir,
    required this.targetDir,
    this.recursive = false,
    required this.mode,
    this.customMappings = const [],
  });

  final String sourceDir;
  final String targetDir;
  final bool recursive;
  final OrganizeMode mode;
  final List<ExtensionMapping> customMappings;
}

class DuplicateScanRequest {
  const DuplicateScanRequest({
    required this.sourceDir,
    this.recursive = false,
    this.includeZeroByte = false,
  });

  final String sourceDir;
  final bool recursive;
  final bool includeZeroByte;
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

String appDataDirectory() {
  final env = Platform.environment;
  if (Platform.isWindows) {
    final base = env['APPDATA'] ?? Directory.systemTemp.path;
    return p.join(base, 'congmiao_toolbox_flutter');
  }
  if (Platform.isMacOS) {
    final base = env['HOME'] ?? Directory.systemTemp.path;
    return p.join(base, 'Library', 'Application Support',
        'congmiao_toolbox_flutter');
  }
  final base = env['XDG_CONFIG_HOME'] ??
      p.join(env['HOME'] ?? Directory.systemTemp.path, '.config');
  return p.join(base, 'congmiao_toolbox_flutter');
}

FileToolsService? _sharedService;

FileToolsService get fileToolsService => _sharedService ??= FileToolsService(
    journalFile: File(p.join(appDataDirectory(), 'file-operations.json')));

class FileToolsService {
  FileToolsService({required this.journalFile});

  final File journalFile;
  final Map<String, _StoredPlan> _plans = {};
  final Map<String, DuplicateScanJob> _jobs = {};

  // -- Previews -------------------------------------------------------------

  FilePlan previewBatchRename(RenamePreviewRequest request) {
    final root = canonicalDir(request.sourceDir);
    final errors = <String>[];
    final files = gatherFiles(root,
        recursive: request.recursive, errors: errors);
    if (files.isEmpty && errors.isNotEmpty) {
      throw FileToolException(errors.join('\n'));
    }
    final raw = <(String, String)>[];
    for (var index = 0; index < files.length; index++) {
      final source = files[index];
      final name = applyRules(source, index,
          includeExtension: request.includeExtension, rules: request.rules);
      raw.add((source, p.join(p.dirname(source), name)));
    }
    return _cachePlan(_buildPlan('rename', raw));
  }

  FilePlan previewFileOrganize(OrganizePreviewRequest request) {
    final sourceRoot = canonicalDir(request.sourceDir);
    final targetRoot = canonicalDir(request.targetDir);
    final mode = request.mode;
    if (mode is OrganizeBySize && mode.smallBytes >= mode.largeBytes) {
      throw const FileToolException('大小阈值必须从小到大');
    }
    final mappings = <String, String>{};
    for (final item in request.customMappings) {
      final ext = item.extension.trim().toLowerCase().replaceFirst(
          RegExp(r'^\.+'), '');
      if (ext.isEmpty) {
        throw const FileToolException('自定义扩展名不能为空');
      }
      mappings[ext] = relativeFolder(item.folder);
    }
    final excluded = !p.equals(targetRoot, sourceRoot) &&
            p.isWithin(sourceRoot, targetRoot)
        ? targetRoot
        : null;
    final errors = <String>[];
    final files = gatherFiles(sourceRoot,
        recursive: request.recursive, excluded: excluded, errors: errors);
    if (files.isEmpty && errors.isNotEmpty) {
      throw FileToolException(errors.join('\n'));
    }
    final raw = <(String, String)>[];
    for (final source in files) {
      final stat = File(source).statSync();
      if (stat.type == FileSystemEntityType.notFound) {
        throw FileToolException('无法读取文件信息：$source');
      }
      final ext = p.extension(source).toLowerCase().replaceFirst('.', '');
      final String folder;
      if (mappings.containsKey(ext)) {
        folder = mappings[ext]!;
      } else {
        switch (mode) {
          case OrganizeByExtension():
            folder = extensionCategory(ext);
          case OrganizeByModifiedDate(:final granularity):
            final date = stat.modified;
            folder = granularity == 'year'
                ? date.year.toString().padLeft(4, '0')
                : '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';
          case OrganizeBySize(:final smallBytes, :final largeBytes):
            folder = stat.size < smallBytes
                ? '小文件'
                : (stat.size < largeBytes ? '中等文件' : '大文件');
        }
      }
      _ensureTargetIsNotSymlink(targetRoot, folder);
      raw.add((source, p.join(targetRoot, folder, p.basename(source))));
    }
    return _cachePlan(_buildPlan('organize', raw));
  }

  _StoredPlan _buildPlan(String kind, List<(String, String)> raw) {
    final sourceKeys = {for (final (source, _) in raw) pathKey(source)};
    final counts = <String, int>{};
    for (final (_, target) in raw) {
      counts.update(pathKey(target), (count) => count + 1, ifAbsent: () => 1);
    }
    final entries = <_StoredEntry>[];
    for (final (source, target) in raw) {
      final stat = File(source).statSync();
      if (stat.type == FileSystemEntityType.notFound) {
        throw FileToolException('$source: 文件不存在');
      }
      final targetName = p.basename(target);
      var reason = filenameError(targetName);
      if (target.length > 240) {
        reason = '目标路径过长';
      }
      if ((counts[pathKey(target)] ?? 0) > 1) {
        reason = '多个文件使用同一目标名称';
      }
      final targetExists =
          FileSystemEntity.typeSync(target) != FileSystemEntityType.notFound;
      if (pathKey(source) != pathKey(target) &&
          targetExists &&
          !(kind == 'rename' && sourceKeys.contains(pathKey(target)))) {
        reason = '目标文件已存在';
      }
      final status = source == target
          ? 'unchanged'
          : (reason != null ? 'invalid' : 'ready');
      entries.add(_StoredEntry(
        entry: FilePlanEntry(
          sourcePath: source,
          targetPath: target,
          originalName: p.basename(source),
          targetName: targetName,
          size: stat.size,
          status: status,
          reason: status == 'invalid' ? reason : null,
        ),
        size: stat.size,
        modifiedMs: _modifiedMs(stat),
      ));
    }
    final public = entries.map((e) => e.entry).toList();
    return _StoredPlan(
      plan: FilePlan(
        planId: generateId(),
        kind: kind,
        createdAt: _nowMs(),
        entries: public,
        readyCount: public.where((e) => e.status == 'ready').length,
        invalidCount: public.where((e) => e.status == 'invalid').length,
      ),
      entries: entries,
    );
  }

  FilePlan _cachePlan(_StoredPlan stored) {
    _plans.removeWhere(
        (_, plan) => DateTime.now().difference(plan.created) >= planTtl);
    _plans[stored.plan.planId] = stored;
    return stored.plan;
  }

  // -- Execute / journal ----------------------------------------------------

  void _verifySource(_StoredEntry stored) {
    final stat = File(stored.entry.sourcePath).statSync();
    if (stat.type == FileSystemEntityType.notFound) {
      throw FileToolException('源文件已不存在：${stored.entry.sourcePath}');
    }
    if (stat.type != FileSystemEntityType.file ||
        stat.size != stored.size ||
        _modifiedMs(stat) != stored.modifiedMs) {
      throw FileToolException('源文件在预览后发生变化：${stored.entry.sourcePath}');
    }
  }

  static void _safeMove(String source, String target) {
    if (FileSystemEntity.typeSync(target) != FileSystemEntityType.notFound) {
      throw FileToolException('目标已存在：$target');
    }
    Directory(p.dirname(target)).createSync(recursive: true);
    try {
      File(source).renameSync(target);
      return;
    } on FileSystemException {
      // Cross-device fallback: copy, flush, promote, then delete the source.
    }
    final temp = p.join(p.dirname(target), '.congmiao-copy-${generateId()}');
    try {
      File(source).copySync(temp);
      final raf = File(temp).openSync(mode: FileMode.append);
      try {
        raf.flushSync();
      } finally {
        raf.closeSync();
      }
      File(temp).renameSync(target);
    } on FileSystemException catch (error) {
      try {
        File(temp).deleteSync();
      } on FileSystemException {
        // Best-effort cleanup.
      }
      throw FileToolException('跨磁盘移动失败：${error.message}');
    }
    try {
      File(source).deleteSync();
    } on FileSystemException catch (error) {
      try {
        File(target).deleteSync();
      } on FileSystemException {
        // Best-effort cleanup.
      }
      throw FileToolException('删除原文件失败：${error.message}');
    }
  }

  static List<(String, String)> _executeRename(List<_StoredEntry> entries) {
    final ready =
        entries.where((entry) => entry.entry.status == 'ready').toList();
    final staged = <(String, String, String)>[];
    for (final stored in ready) {
      final source = stored.entry.sourcePath;
      final temp =
          p.join(p.dirname(source), '.congmiao-rename-${generateId()}');
      try {
        File(source).renameSync(temp);
      } on FileSystemException catch (error) {
        for (final (original, stagedPath, _) in staged.reversed) {
          try {
            File(stagedPath).renameSync(original);
          } on FileSystemException {
            // Keep rolling back the rest.
          }
        }
        throw FileToolException('暂存重命名失败：${error.message}');
      }
      staged.add((source, temp, stored.entry.targetPath));
    }
    final completed = <(String, String)>[];
    for (var index = 0; index < staged.length; index++) {
      final (source, temp, target) = staged[index];
      try {
        File(temp).renameSync(target);
      } on FileSystemException catch (error) {
        for (final (old, moved) in completed.reversed) {
          try {
            File(moved).renameSync(old);
          } on FileSystemException {
            // Keep rolling back the rest.
          }
        }
        for (final (old, tmp, _) in staged.sublist(index).reversed) {
          try {
            File(tmp).renameSync(old);
          } on FileSystemException {
            // Keep rolling back the rest.
          }
        }
        throw FileToolException('应用重命名失败并已尝试回滚：${error.message}');
      }
      completed.add((source, target));
    }
    return completed;
  }

  static List<(String, String)> _executeOrganize(List<_StoredEntry> entries) {
    final completed = <(String, String)>[];
    for (final stored
        in entries.where((entry) => entry.entry.status == 'ready')) {
      try {
        _safeMove(stored.entry.sourcePath, stored.entry.targetPath);
      } on FileToolException catch (error) {
        for (final (old, moved) in completed.reversed) {
          try {
            _safeMove(moved, old);
          } on FileToolException {
            // Keep rolling back the rest.
          }
        }
        throw FileToolException('整理失败并已尝试回滚：${error.message}');
      }
      completed.add((stored.entry.sourcePath, stored.entry.targetPath));
    }
    return completed;
  }

  static List<_StoredEntry> _inverseEntries(FileOperationRecord record) =>
      record.moves
          .map((move) => _StoredEntry(
                entry: FilePlanEntry(
                  sourcePath: move.targetPath,
                  targetPath: move.sourcePath,
                  originalName: '',
                  targetName: '',
                  size: move.size,
                  status: 'ready',
                ),
                size: move.size,
                modifiedMs: move.modifiedMs,
              ))
          .toList();

  static void _rollbackRecord(FileOperationRecord record) {
    if (record.kind == 'rename') {
      _executeRename(_inverseEntries(record));
    } else {
      for (final move in record.moves.reversed) {
        _safeMove(move.targetPath, move.sourcePath);
      }
    }
  }

  List<FileOperationRecord> _loadJournal() {
    final path = journalFile.path;
    final backup = File('$path.bak');
    var source = journalFile;
    if (!journalFile.existsSync()) {
      if (!backup.existsSync()) return [];
      backup.renameSync(path);
      source = File(path);
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(source.readAsStringSync());
    } on FormatException catch (error) {
      throw FileToolException('操作日志损坏：${error.message}');
    }
    if (decoded is! Map<String, dynamic> || decoded['operations'] is! List) {
      throw const FileToolException('操作日志损坏：结构不完整');
    }
    return (decoded['operations'] as List)
        .whereType<Map<String, dynamic>>()
        .map(FileOperationRecord.fromJson)
        .toList();
  }

  void _saveJournal(List<FileOperationRecord> operations) {
    journalFile.parent.createSync(recursive: true);
    final path = journalFile.path;
    final temp = File('$path.tmp');
    final backup = File('$path.bak');
    temp.writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
      'schemaVersion': 1,
      'operations': operations.map((record) => record.toJson()).toList(),
    }));
    if (backup.existsSync()) backup.deleteSync();
    if (journalFile.existsSync()) journalFile.renameSync(backup.path);
    try {
      temp.renameSync(path);
    } on FileSystemException catch (error) {
      if (backup.existsSync()) {
        try {
          backup.renameSync(path);
        } on FileSystemException {
          // Leave the backup in place for manual recovery.
        }
      }
      throw FileToolException(error.message);
    }
    if (backup.existsSync()) {
      try {
        backup.deleteSync();
      } on FileSystemException {
        // Stale backup is harmless.
      }
    }
  }

  FileOperationRecord executePlan(String planId) {
    final stored = _plans.remove(planId);
    if (stored == null) {
      throw const FileToolException('预览已失效，请重新预览');
    }
    if (DateTime.now().difference(stored.created) >= planTtl) {
      throw const FileToolException('预览已超过 10 分钟，请重新预览');
    }
    if (stored.plan.invalidCount > 0 || stored.plan.readyCount == 0) {
      throw const FileToolException('预览包含冲突或没有可执行项目');
    }
    final operations = _loadJournal();
    for (final entry
        in stored.entries.where((entry) => entry.entry.status == 'ready')) {
      _verifySource(entry);
    }
    final moved = stored.plan.kind == 'rename'
        ? _executeRename(stored.entries)
        : _executeOrganize(stored.entries);
    final moves = <OperationMove>[];
    for (final (source, target) in moved) {
      final stat = File(target).statSync();
      moves.add(OperationMove(
        sourcePath: source,
        targetPath: target,
        size: stat.size,
        modifiedMs: _modifiedMs(stat),
      ));
    }
    final record = FileOperationRecord(
      id: generateId(),
      kind: stored.plan.kind,
      createdAt: _nowMs(),
      undone: false,
      moves: moves,
    );
    operations.insert(0, record);
    if (operations.length > journalLimit) {
      operations.removeRange(journalLimit, operations.length);
    }
    try {
      _saveJournal(operations);
    } on FileToolException catch (error) {
      try {
        _rollbackRecord(record);
      } on FileToolException catch (rollback) {
        throw FileToolException(
            '写入撤销日志失败：${error.message}；回滚也失败：${rollback.message}');
      }
      throw FileToolException('写入撤销日志失败，文件操作已回滚：${error.message}');
    }
    return record;
  }

  List<FileOperationRecord> listOperations() => _loadJournal();

  void clearOperationHistory() => _saveJournal([]);

  FileOperationRecord undoOperation(String operationId) {
    final operations = _loadJournal();
    final index = operations.indexWhere((record) => record.id == operationId);
    if (index == -1) {
      throw const FileToolException('找不到操作记录');
    }
    final record = operations[index];
    if (record.undone) {
      throw const FileToolException('该操作已经撤销');
    }
    final movedTargetKeys = {
      for (final move in record.moves) pathKey(move.targetPath),
    };
    for (final move in record.moves) {
      final stat = File(move.targetPath).statSync();
      if (stat.type == FileSystemEntityType.notFound) {
        throw FileToolException('目标文件已不存在：${move.targetPath}');
      }
      if (stat.size != move.size || _modifiedMs(stat) != move.modifiedMs) {
        throw FileToolException('目标文件已被修改：${move.targetPath}');
      }
      final sourceExists = FileSystemEntity.typeSync(move.sourcePath) !=
          FileSystemEntityType.notFound;
      if (sourceExists && !movedTargetKeys.contains(pathKey(move.sourcePath))) {
        throw FileToolException('原路径已被占用：${move.sourcePath}');
      }
    }
    if (record.kind == 'rename') {
      _executeRename(_inverseEntries(record));
    } else {
      final restored = <(String, String)>[];
      for (final move in record.moves.reversed) {
        try {
          _safeMove(move.targetPath, move.sourcePath);
        } on FileToolException catch (error) {
          for (final (old, moved) in restored.reversed) {
            try {
              _safeMove(old, moved);
            } on FileToolException {
              // Keep restoring the rest.
            }
          }
          throw FileToolException('撤销失败并已尝试恢复：${error.message}');
        }
        restored.add((move.sourcePath, move.targetPath));
      }
    }
    record.undone = true;
    _saveJournal(operations);
    return record;
  }

  // -- Duplicate scan ---------------------------------------------------------

  DuplicateScanJob startDuplicateScan(
    DuplicateScanRequest request, {
    void Function(FileJobProgress progress)? onProgress,
  }) {
    canonicalDir(request.sourceDir);
    final job = DuplicateScanJob._(generateId(), _CancelFlag());
    _jobs[job.jobId] = job;
    job.done = _scanDuplicates(job, request, onProgress).whenComplete(() {
      _jobs.remove(job.jobId);
    });
    return job;
  }

  void cancelJob(String jobId) {
    final job = _jobs[jobId];
    if (job == null) {
      throw const FileToolException('扫描任务不存在或已经结束');
    }
    job.cancel();
  }

  Future<DuplicateScanComplete> _scanDuplicates(
    DuplicateScanJob job,
    DuplicateScanRequest request,
    void Function(FileJobProgress progress)? onProgress,
  ) async {
    DuplicateScanComplete cancelled(List<String> errors, int scanned) =>
        DuplicateScanComplete(
          jobId: job.jobId,
          cancelled: true,
          groups: const [],
          errors: errors,
          scannedFiles: scanned,
          reclaimableBytes: 0,
        );

    final root = canonicalDir(request.sourceDir);
    final errors = <String>[];
    final files =
        gatherFiles(root, recursive: request.recursive, errors: errors);
    final scannedFiles = files.length;

    final sizes = <int, List<String>>{};
    for (final path in files) {
      final stat = File(path).statSync();
      if (stat.type == FileSystemEntityType.notFound) {
        errors.add('$path: 文件不存在');
      } else if (request.includeZeroByte || stat.size > 0) {
        sizes.putIfAbsent(stat.size, () => []).add(path);
      }
    }

    final candidates = <(int, String)>[
      for (final entry in sizes.entries)
        if (entry.value.length > 1)
          for (final path in entry.value) (entry.key, path),
    ];
    final totalBytes = candidates.fold<int>(0, (sum, item) => sum + item.$1);

    final sampled = <String, List<(int, String)>>{};
    for (var index = 0; index < candidates.length; index++) {
      if (job._cancelled.value) return cancelled(errors, scannedFiles);
      final (size, path) = candidates[index];
      try {
        final hash = await _sampleHash(path, size);
        sampled.putIfAbsent('$size:$hash', () => []).add((size, path));
      } on FileSystemException catch (error) {
        errors.add('$path: ${error.message}');
      } on FileToolException catch (error) {
        errors.add('$path: ${error.message}');
      }
      onProgress?.call(FileJobProgress(
        jobId: job.jobId,
        stage: 'sample',
        processedFiles: index + 1,
        totalFiles: candidates.length,
        processedBytes: 0,
        totalBytes: totalBytes,
        errorCount: errors.length,
      ));
    }

    final full = <(int, String)>[
      for (final group in sampled.values)
        if (group.length > 1) ...group,
    ];
    final fullTotalBytes = full.fold<int>(0, (sum, item) => sum + item.$1);

    final hashes = <String, List<(int, String)>>{};
    var processedBytes = 0;
    for (var index = 0; index < full.length; index++) {
      final (size, path) = full[index];
      try {
        final hash = await _fullHash(path, job._cancelled);
        hashes.putIfAbsent('$size:$hash', () => []).add((size, path));
      } on _CancelledException {
        return cancelled(errors, scannedFiles);
      } on FileSystemException catch (error) {
        errors.add('$path: ${error.message}');
      }
      processedBytes += size;
      onProgress?.call(FileJobProgress(
        jobId: job.jobId,
        stage: 'fullHash',
        processedFiles: index + 1,
        totalFiles: full.length,
        processedBytes: processedBytes,
        totalBytes: fullTotalBytes,
        errorCount: errors.length,
      ));
    }

    final groups = <DuplicateGroup>[
      for (final entry in hashes.entries)
        if (entry.value.length > 1)
          DuplicateGroup(
            hash: entry.key.split(':').last,
            size: entry.value.first.$1,
            paths: [for (final (_, path) in entry.value) path],
            reclaimableBytes:
                entry.value.first.$1 * (entry.value.length - 1),
          ),
    ]..sort((a, b) => b.reclaimableBytes.compareTo(a.reclaimableBytes));

    return DuplicateScanComplete(
      jobId: job.jobId,
      cancelled: false,
      groups: groups,
      errors: errors,
      scannedFiles: scannedFiles,
      reclaimableBytes:
          groups.fold<int>(0, (sum, group) => sum + group.reclaimableBytes),
    );
  }

  Future<String> _sampleHash(String path, int size) async {
    final raf = await File(path).open();
    try {
      final sink = _DigestSink();
      final input = sha256.startChunkedConversion(sink);
      final firstLen = math.min(size, sampleSize);
      final first = await raf.read(firstLen);
      if (first.length != firstLen) {
        throw const FileToolException('读取文件失败');
      }
      input.add(first);
      if (size > sampleSize) {
        final tailLen = math.min(size, sampleSize);
        await raf.setPosition(size - tailLen);
        final tail = await raf.read(tailLen);
        if (tail.length != tailLen) {
          throw const FileToolException('读取文件失败');
        }
        input.add(tail);
      }
      input.close();
      return sink.value.toString();
    } finally {
      await raf.close();
    }
  }

  Future<String> _fullHash(String path, _CancelFlag cancel) async {
    final sink = _DigestSink();
    final input = sha256.startChunkedConversion(sink);
    await for (final chunk in File(path).openRead()) {
      if (cancel.value) throw const _CancelledException();
      input.add(chunk);
    }
    input.close();
    return sink.value.toString();
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

// ---------------------------------------------------------------------------
// Test hooks (reach library-private plan/rename internals from unit tests)
// ---------------------------------------------------------------------------

FilePlan debugBuildPlan(String kind, List<(String, String)> raw) =>
    FileToolsService(journalFile: File('unused'))._buildPlan(kind, raw).plan;

List<(String, String)> debugExecuteRenamePairs(List<(String, String)> pairs) =>
    FileToolsService._executeRename([
      for (final (source, target) in pairs)
        _StoredEntry(
          entry: FilePlanEntry(
            sourcePath: source,
            targetPath: target,
            originalName: '',
            targetName: '',
            size: 0,
            status: 'ready',
          ),
          size: 0,
          modifiedMs: 0,
        ),
    ]);
