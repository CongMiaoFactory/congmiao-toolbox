import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../core/file_tools.dart';

/// Shared building blocks for the three file tools (FilePlanTable.svelte /
/// OperationHistory.svelte counterparts).
class DirectoryField extends StatelessWidget {
  const DirectoryField({
    super.key,
    required this.controller,
    required this.label,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String label;
  final bool enabled;

  Future<void> _browse() async {
    final selected = await getDirectoryPath(confirmButtonText: '选择');
    if (selected != null) controller.text = selected;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            enabled: enabled,
            decoration: InputDecoration(
              labelText: label,
              hintText: '粘贴路径或点击浏览…',
              isDense: true,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.folder_open, size: 16),
          label: const Text('浏览'),
          onPressed: enabled ? _browse : null,
        ),
      ],
    );
  }
}

class FilePlanTable extends StatelessWidget {
  const FilePlanTable({super.key, required this.plan});

  final FilePlan plan;

  Color _statusColor(BuildContext context, String status) {
    switch (status) {
      case 'ready':
        return const Color(0xFF4ADE80);
      case 'invalid':
        return Theme.of(context).colorScheme.error;
      default:
        return Theme.of(context).hintColor;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'ready':
        return '就绪';
      case 'invalid':
        return '冲突';
      default:
        return '不变';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            '共 ${plan.entries.length} 项 · ${plan.readyCount} 就绪 · '
            '${plan.invalidCount} 冲突 · '
            '${plan.entries.length - plan.readyCount - plan.invalidCount} 不变',
            style: theme.textTheme.labelMedium,
          ),
        ),
        Expanded(
          child: plan.entries.isEmpty
              ? Center(
                  child: Text('目录中没有文件', style: theme.textTheme.bodySmall))
              : ListView.builder(
                  itemCount: plan.entries.length,
                  itemBuilder: (context, index) {
                    final entry = plan.entries[index];
                    final color = _statusColor(context, entry.status);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _statusLabel(entry.status),
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(color: color),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              entry.originalName,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                          const Icon(Icons.arrow_forward, size: 12),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              entry.reason ?? entry.targetName,
                              overflow: TextOverflow.ellipsis,
                              style: entry.reason != null
                                  ? theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.error)
                                  : theme.textTheme.bodySmall,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(formatBytes(entry.size),
                              style: theme.textTheme.labelSmall),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class OperationHistoryPanel extends StatefulWidget {
  const OperationHistoryPanel({
    super.key,
    required this.onMessage,
    this.refreshSignal = 0,
  });

  /// Bumped by the parent after an execute so the list reloads.
  final int refreshSignal;
  final void Function(String message, {bool isError}) onMessage;

  @override
  State<OperationHistoryPanel> createState() => _OperationHistoryPanelState();
}

class _OperationHistoryPanelState extends State<OperationHistoryPanel> {
  List<FileOperationRecord> _records = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(OperationHistoryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshSignal != widget.refreshSignal) _reload();
  }

  void _reload() {
    try {
      setState(() {
        _records = fileToolsService.listOperations();
        _error = null;
      });
    } on FileToolException catch (error) {
      setState(() => _error = error.message);
    }
  }

  void _undo(FileOperationRecord record) {
    try {
      fileToolsService.undoOperation(record.id);
      widget.onMessage('已撤销 ${record.moves.length} 个文件的移动');
    } on FileToolException catch (error) {
      widget.onMessage(error.message, isError: true);
    }
    _reload();
  }

  void _clear() {
    try {
      fileToolsService.clearOperationHistory();
    } on FileToolException catch (error) {
      widget.onMessage(error.message, isError: true);
    }
    _reload();
  }

  String _timestamp(int ms) {
    final at = DateTime.fromMillisecondsSinceEpoch(ms);
    String pad(int value) => value.toString().padLeft(2, '0');
    return '${pad(at.month)}-${pad(at.day)} ${pad(at.hour)}:${pad(at.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text('操作历史（最近 $journalLimit 条，可撤销）',
                style: theme.textTheme.labelLarge),
            const Spacer(),
            IconButton(
              tooltip: '刷新',
              iconSize: 16,
              icon: const Icon(Icons.refresh),
              onPressed: _reload,
            ),
            TextButton(onPressed: _clear, child: const Text('清空')),
          ],
        ),
        if (_error != null)
          Text(_error!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error))
        else if (_records.isEmpty)
          Text('暂无操作记录', style: theme.textTheme.bodySmall)
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 130),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _records.length,
              itemBuilder: (context, index) {
                final record = _records[index];
                return Row(
                  children: [
                    Icon(
                      record.kind == 'rename'
                          ? Icons.drive_file_rename_outline
                          : Icons.sort,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${record.kind == 'rename' ? '重命名' : '整理'} '
                        '${record.moves.length} 个文件 · '
                        '${_timestamp(record.createdAt)}',
                        style: theme.textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    record.undone
                        ? Text('已撤销', style: theme.textTheme.labelSmall)
                        : TextButton(
                            onPressed: () => _undo(record),
                            child: const Text('撤销'),
                          ),
                  ],
                );
              },
            ),
          ),
      ],
    );
  }
}
