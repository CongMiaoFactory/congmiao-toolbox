import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/file_tools.dart';
import '../core/tool_registry.dart';
import 'file_widgets.dart';

/// Duplicate scanner window (DuplicateScannerTool.svelte): staged size →
/// sample-hash → full-hash pipeline producing a read-only report.
class DuplicateScannerTool extends StatefulWidget {
  const DuplicateScannerTool({super.key, required this.appState});

  final AppState appState;

  @override
  State<DuplicateScannerTool> createState() => _DuplicateScannerToolState();
}

class _DuplicateScannerToolState extends State<DuplicateScannerTool> {
  final TextEditingController _dirController = TextEditingController();
  bool _recursive = true;
  bool _includeZeroByte = false;
  DuplicateScanJob? _job;
  FileJobProgress? _progress;
  DuplicateScanComplete? _result;
  String? _error;

  @override
  void dispose() {
    _job?.cancel();
    _dirController.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _error = null;
      _result = null;
      _progress = null;
    });
    final DuplicateScanJob job;
    try {
      job = fileToolsService.startDuplicateScan(
        DuplicateScanRequest(
          sourceDir: _dirController.text,
          recursive: _recursive,
          includeZeroByte: _includeZeroByte,
        ),
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
      );
    } on FileToolException catch (error) {
      setState(() => _error = error.message);
      return;
    }
    setState(() => _job = job);
    final result = await job.done;
    if (!mounted) return;
    setState(() {
      _job = null;
      _result = result;
    });
    if (!result.cancelled) {
      widget.appState.addActivity(
        source: 'FILE',
        title: '重复文件扫描',
        value:
            '${result.groups.length} 组重复，可释放 ${formatBytes(result.reclaimableBytes)}',
        accent: ToolAccent.purple,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = _progress;
    final result = _result;
    final running = _job != null;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DirectoryField(
              controller: _dirController, label: '扫描目录', enabled: !running),
          const SizedBox(height: 8),
          Row(children: [
            Checkbox(
              value: _recursive,
              visualDensity: VisualDensity.compact,
              onChanged: running
                  ? null
                  : (v) => setState(() => _recursive = v ?? true),
            ),
            const Text('包含子目录'),
            const SizedBox(width: 12),
            Checkbox(
              value: _includeZeroByte,
              visualDensity: VisualDensity.compact,
              onChanged: running
                  ? null
                  : (v) => setState(() => _includeZeroByte = v ?? false),
            ),
            const Text('包含 0 字节文件'),
            const Spacer(),
            if (running)
              OutlinedButton.icon(
                icon: const Icon(Icons.stop, size: 16),
                label: const Text('取消'),
                onPressed: () => _job?.cancel(),
              )
            else
              FilledButton.icon(
                icon: const Icon(Icons.search, size: 16),
                label: const Text('开始扫描'),
                onPressed: _start,
              ),
          ]),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(_error!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error)),
            ),
          if (running || progress != null) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: progress == null || progress.totalFiles == 0
                  ? null
                  : progress.processedFiles / progress.totalFiles,
            ),
            const SizedBox(height: 4),
            Text(
              progress == null
                  ? '正在收集文件…'
                  : '${progress.stage == 'sample' ? '抽样哈希' : '全量哈希'} '
                      '${progress.processedFiles}/${progress.totalFiles} 个文件'
                      '${progress.stage == 'fullHash' ? ' · ${formatBytes(progress.processedBytes)}/${formatBytes(progress.totalBytes)}' : ''}'
                      '${progress.errorCount > 0 ? ' · ${progress.errorCount} 个错误' : ''}',
              style: theme.textTheme.labelSmall,
            ),
          ],
          const SizedBox(height: 8),
          Expanded(
            child: result == null
                ? Center(
                    child: Text(
                      running ? '扫描中…' : '选择目录后开始扫描。报告为只读，不会改动任何文件。',
                      style: theme.textTheme.bodySmall,
                    ),
                  )
                : _buildResult(theme, result),
          ),
        ],
      ),
    );
  }

  Widget _buildResult(ThemeData theme, DuplicateScanComplete result) {
    if (result.cancelled) {
      return Center(
          child: Text('扫描已取消', style: theme.textTheme.bodyMedium));
    }
    if (result.groups.isEmpty) {
      return Center(
        child: Text(
          '扫描了 ${result.scannedFiles} 个文件，未发现重复'
          '${result.errors.isNotEmpty ? '（${result.errors.length} 个读取错误）' : ''}',
          style: theme.textTheme.bodyMedium,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '扫描 ${result.scannedFiles} 个文件 · ${result.groups.length} 组重复 · '
          '删除多余副本可释放 ${formatBytes(result.reclaimableBytes)}'
          '${result.errors.isNotEmpty ? ' · ${result.errors.length} 个读取错误' : ''}',
          style: theme.textTheme.labelMedium,
        ),
        const SizedBox(height: 6),
        Expanded(
          child: ListView.builder(
            itemCount: result.groups.length,
            itemBuilder: (context, index) {
              final group = result.groups[index];
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${group.paths.length} 个相同文件 · 单个 ${formatBytes(group.size)} · '
                        '可释放 ${formatBytes(group.reclaimableBytes)}',
                        style: theme.textTheme.labelLarge,
                      ),
                      const SizedBox(height: 4),
                      for (final path in group.paths)
                        SelectableText(path,
                            style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
