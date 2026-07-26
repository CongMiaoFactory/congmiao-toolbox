import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/file_tools.dart';
import '../core/tool_registry.dart';
import 'file_widgets.dart';

/// Rule-based organizer window (FileOrganizerTool.svelte): move files into
/// category folders by type / modified date / size, preview first, undoable.
class FileOrganizerTool extends StatefulWidget {
  const FileOrganizerTool({super.key, required this.appState});

  final AppState appState;

  @override
  State<FileOrganizerTool> createState() => _FileOrganizerToolState();
}

class _MappingDraft {
  String extension = '';
  String folder = '';
}

class _FileOrganizerToolState extends State<FileOrganizerTool> {
  final TextEditingController _sourceController = TextEditingController();
  final TextEditingController _targetController = TextEditingController();
  final List<_MappingDraft> _mappings = [];
  bool _recursive = false;
  String _mode = 'extension'; // extension | date | size
  String _granularity = 'month';
  String _smallMb = '10';
  String _largeMb = '500';
  FilePlan? _plan;
  String? _message;
  bool _messageIsError = false;
  int _historyRefresh = 0;

  @override
  void dispose() {
    _sourceController.dispose();
    _targetController.dispose();
    super.dispose();
  }

  void _notify(String message, {bool isError = false}) {
    setState(() {
      _message = message;
      _messageIsError = isError;
      if (!isError) _historyRefresh++;
    });
  }

  OrganizeMode _buildMode() {
    switch (_mode) {
      case 'date':
        return OrganizeByModifiedDate(_granularity);
      case 'size':
        final small = (double.tryParse(_smallMb.trim()) ?? 10) * 1024 * 1024;
        final large = (double.tryParse(_largeMb.trim()) ?? 500) * 1024 * 1024;
        return OrganizeBySize(
            smallBytes: small.round(), largeBytes: large.round());
      default:
        return const OrganizeByExtension();
    }
  }

  void _preview() {
    try {
      final plan = fileToolsService.previewFileOrganize(OrganizePreviewRequest(
        sourceDir: _sourceController.text,
        targetDir: _targetController.text.trim().isEmpty
            ? _sourceController.text
            : _targetController.text,
        recursive: _recursive,
        mode: _buildMode(),
        customMappings: [
          for (final draft in _mappings)
            if (draft.extension.trim().isNotEmpty)
              ExtensionMapping(
                  extension: draft.extension, folder: draft.folder),
        ],
      ));
      setState(() {
        _plan = plan;
        _message = null;
      });
    } on FileToolException catch (error) {
      setState(() {
        _plan = null;
        _message = error.message;
        _messageIsError = true;
      });
    }
  }

  void _execute() {
    final plan = _plan;
    if (plan == null) return;
    try {
      final record = fileToolsService.executePlan(plan.planId);
      setState(() => _plan = null);
      _notify('已整理 ${record.moves.length} 个文件，可在下方历史中撤销');
      widget.appState.addActivity(
        source: 'FILE',
        title: '规则整理文件',
        value: '移动 ${record.moves.length} 个文件',
        accent: ToolAccent.green,
      );
    } on FileToolException catch (error) {
      _notify(error.message, isError: true);
    }
  }

  Widget _modeOptions(ThemeData theme) {
    switch (_mode) {
      case 'date':
        return Row(children: [
          Text('归档粒度：', style: theme.textTheme.bodySmall),
          DropdownButton<String>(
            value: _granularity,
            items: const [
              DropdownMenuItem(value: 'month', child: Text('按月 (YYYY-MM)')),
              DropdownMenuItem(value: 'year', child: Text('按年 (YYYY)')),
            ],
            onChanged: (v) => setState(() => _granularity = v ?? 'month'),
          ),
        ]);
      case 'size':
        return Row(children: [
          SizedBox(
            width: 110,
            child: TextFormField(
              initialValue: _smallMb,
              onChanged: (v) => _smallMb = v,
              decoration: const InputDecoration(
                labelText: '小文件上限 MB',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 110,
            child: TextFormField(
              initialValue: _largeMb,
              onChanged: (v) => _largeMb = v,
              decoration: const InputDecoration(
                labelText: '大文件下限 MB',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ]);
      default:
        return Text('按图片 / 视频 / 音频 / 文档 / 压缩包 / 代码 / 其他分类',
            style: theme.textTheme.bodySmall);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plan = _plan;
    final canExecute =
        plan != null && plan.invalidCount == 0 && plan.readyCount > 0;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DirectoryField(controller: _sourceController, label: '源目录'),
          const SizedBox(height: 8),
          DirectoryField(
              controller: _targetController, label: '目标目录（留空 = 源目录）'),
          const SizedBox(height: 8),
          Row(children: [
            Checkbox(
              value: _recursive,
              visualDensity: VisualDensity.compact,
              onChanged: (v) => setState(() => _recursive = v ?? false),
            ),
            const Text('包含子目录'),
            const SizedBox(width: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'extension', label: Text('按类型')),
                ButtonSegment(value: 'date', label: Text('按日期')),
                ButtonSegment(value: 'size', label: Text('按大小')),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
            const Spacer(),
            FilledButton.tonal(onPressed: _preview, child: const Text('预览')),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: canExecute ? _execute : null,
              child: const Text('执行'),
            ),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: _modeOptions(theme)),
            TextButton.icon(
              icon: const Icon(Icons.add, size: 14),
              label: const Text('自定义扩展名映射'),
              onPressed: () => setState(() => _mappings.add(_MappingDraft())),
            ),
          ]),
          if (_mappings.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 96),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final draft in _mappings)
                    Padding(
                      key: ObjectKey(draft),
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(children: [
                        SizedBox(
                          width: 120,
                          child: TextFormField(
                            initialValue: draft.extension,
                            onChanged: (v) => draft.extension = v,
                            decoration: const InputDecoration(
                              labelText: '扩展名',
                              hintText: 'pdf',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            initialValue: draft.folder,
                            onChanged: (v) => draft.folder = v,
                            decoration: const InputDecoration(
                              labelText: '目标子文件夹',
                              hintText: '文档/合同',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        IconButton(
                          iconSize: 16,
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () =>
                              setState(() => _mappings.remove(draft)),
                        ),
                      ]),
                    ),
                ],
              ),
            ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                _message!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _messageIsError
                      ? theme.colorScheme.error
                      : const Color(0xFF4ADE80),
                ),
              ),
            ),
          Expanded(
            child: plan == null
                ? Center(
                    child: Text('选择目录与规则后点击预览，确认无冲突再执行',
                        style: theme.textTheme.bodySmall),
                  )
                : FilePlanTable(plan: plan),
          ),
          const Divider(height: 16),
          OperationHistoryPanel(
              refreshSignal: _historyRefresh, onMessage: _notify),
        ],
      ),
    );
  }
}
