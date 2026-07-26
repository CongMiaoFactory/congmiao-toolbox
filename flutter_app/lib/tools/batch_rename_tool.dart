import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/file_tools.dart';
import '../core/tool_registry.dart';
import 'file_widgets.dart';

/// Batch rename window (BatchRenameTool.svelte): rule chain → preview plan →
/// execute → undo via the shared operation journal.
class BatchRenameTool extends StatefulWidget {
  const BatchRenameTool({super.key, required this.appState});

  final AppState appState;

  @override
  State<BatchRenameTool> createState() => _BatchRenameToolState();
}

class _RuleDraft {
  _RuleDraft(this.type);

  final String type;
  String value = '';
  String find = '';
  String replacement = '';
  bool caseSensitive = false;
  String start = '1';
  String step = '1';
  String padding = '3';
  String position = 'suffix';
  String separator = '_';
  String caseMode = 'lower';
  String dateFormat = 'YYYY-MM-DD';

  RenameRule toRule() {
    switch (type) {
      case 'prefix':
        return PrefixRule(value);
      case 'suffix':
        return SuffixRule(value);
      case 'replace':
        return ReplaceRule(
            find: find, replacement: replacement, caseSensitive: caseSensitive);
      case 'sequence':
        return SequenceRule(
          start: int.tryParse(start.trim()) ?? 1,
          step: int.tryParse(step.trim()) ?? 1,
          padding: int.tryParse(padding.trim()) ?? 0,
          position: position,
          separator: separator,
        );
      case 'case':
        return CaseRule(caseMode);
      default:
        return ModifiedDateRule(
            format: dateFormat, position: position, separator: separator);
    }
  }

  String get label {
    switch (type) {
      case 'prefix':
        return '加前缀';
      case 'suffix':
        return '加后缀';
      case 'replace':
        return '查找替换';
      case 'sequence':
        return '序号';
      case 'case':
        return '大小写';
      default:
        return '修改日期';
    }
  }
}

class _BatchRenameToolState extends State<BatchRenameTool> {
  final TextEditingController _dirController = TextEditingController();
  final List<_RuleDraft> _rules = [_RuleDraft('sequence')];
  bool _recursive = false;
  bool _includeExtension = false;
  FilePlan? _plan;
  String? _message;
  bool _messageIsError = false;
  int _historyRefresh = 0;

  @override
  void dispose() {
    _dirController.dispose();
    super.dispose();
  }

  void _notify(String message, {bool isError = false}) {
    setState(() {
      _message = message;
      _messageIsError = isError;
      if (!isError) _historyRefresh++;
    });
  }

  void _preview() {
    if (_rules.isEmpty) {
      _notify('请至少添加一条重命名规则', isError: true);
      return;
    }
    try {
      final plan = fileToolsService.previewBatchRename(RenamePreviewRequest(
        sourceDir: _dirController.text,
        recursive: _recursive,
        includeExtension: _includeExtension,
        rules: _rules.map((draft) => draft.toRule()).toList(),
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
      _notify('已重命名 ${record.moves.length} 个文件，可在下方历史中撤销');
      widget.appState.addActivity(
        source: 'FILE',
        title: '批量重命名',
        value: '重命名 ${record.moves.length} 个文件',
        accent: ToolAccent.blue,
      );
    } on FileToolException catch (error) {
      _notify(error.message, isError: true);
    }
  }

  Widget _ruleFields(_RuleDraft draft) {
    switch (draft.type) {
      case 'prefix' || 'suffix':
        return _text('文本', draft.value, (v) => draft.value = v);
      case 'replace':
        return Row(children: [
          Expanded(child: _text('查找', draft.find, (v) => draft.find = v)),
          const SizedBox(width: 8),
          Expanded(
              child: _text(
                  '替换为', draft.replacement, (v) => draft.replacement = v)),
          const SizedBox(width: 8),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Checkbox(
              value: draft.caseSensitive,
              visualDensity: VisualDensity.compact,
              onChanged: (v) =>
                  setState(() => draft.caseSensitive = v ?? false),
            ),
            const Text('区分大小写'),
          ]),
        ]);
      case 'sequence':
        return Row(children: [
          SizedBox(
              width: 72, child: _text('起始', draft.start, (v) => draft.start = v)),
          const SizedBox(width: 8),
          SizedBox(
              width: 72, child: _text('步长', draft.step, (v) => draft.step = v)),
          const SizedBox(width: 8),
          SizedBox(
              width: 72,
              child: _text('补零位', draft.padding, (v) => draft.padding = v)),
          const SizedBox(width: 8),
          SizedBox(
              width: 88,
              child:
                  _text('分隔符', draft.separator, (v) => draft.separator = v)),
          const SizedBox(width: 8),
          _positionSelector(draft),
        ]);
      case 'case':
        return SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'lower', label: Text('小写')),
            ButtonSegment(value: 'upper', label: Text('大写')),
          ],
          selected: {draft.caseMode},
          onSelectionChanged: (s) => setState(() => draft.caseMode = s.first),
        );
      default:
        return Row(children: [
          DropdownButton<String>(
            value: draft.dateFormat,
            items: const [
              DropdownMenuItem(
                  value: 'YYYY-MM-DD', child: Text('YYYY-MM-DD')),
              DropdownMenuItem(value: 'YYYYMMDD', child: Text('YYYYMMDD')),
            ],
            onChanged: (v) =>
                setState(() => draft.dateFormat = v ?? 'YYYY-MM-DD'),
          ),
          const SizedBox(width: 8),
          SizedBox(
              width: 88,
              child:
                  _text('分隔符', draft.separator, (v) => draft.separator = v)),
          const SizedBox(width: 8),
          _positionSelector(draft),
        ]);
    }
  }

  Widget _positionSelector(_RuleDraft draft) {
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(value: 'prefix', label: Text('前')),
        ButtonSegment(value: 'suffix', label: Text('后')),
      ],
      selected: {draft.position},
      onSelectionChanged: (s) => setState(() => draft.position = s.first),
    );
  }

  Widget _text(String label, String initial, void Function(String) onChanged) {
    return TextFormField(
      initialValue: initial,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    );
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
          DirectoryField(controller: _dirController, label: '源目录'),
          const SizedBox(height: 8),
          Row(children: [
            Checkbox(
              value: _recursive,
              visualDensity: VisualDensity.compact,
              onChanged: (v) => setState(() => _recursive = v ?? false),
            ),
            const Text('包含子目录'),
            const SizedBox(width: 12),
            Checkbox(
              value: _includeExtension,
              visualDensity: VisualDensity.compact,
              onChanged: (v) =>
                  setState(() => _includeExtension = v ?? false),
            ),
            const Text('规则作用于扩展名'),
            const Spacer(),
            PopupMenuButton<String>(
              tooltip: '添加规则',
              onSelected: (type) =>
                  setState(() => _rules.add(_RuleDraft(type))),
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'prefix', child: Text('加前缀')),
                PopupMenuItem(value: 'suffix', child: Text('加后缀')),
                PopupMenuItem(value: 'replace', child: Text('查找替换')),
                PopupMenuItem(value: 'sequence', child: Text('序号')),
                PopupMenuItem(value: 'case', child: Text('大小写')),
                PopupMenuItem(value: 'modifiedDate', child: Text('修改日期')),
              ],
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.add, size: 16),
                  Text('添加规则'),
                ]),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(onPressed: _preview, child: const Text('预览')),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: canExecute ? _execute : null,
              child: const Text('执行'),
            ),
          ]),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 168),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final draft in _rules)
                  Padding(
                    key: ObjectKey(draft),
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 72,
                          child: Text(draft.label,
                              style: theme.textTheme.labelMedium),
                        ),
                        Expanded(child: _ruleFields(draft)),
                        IconButton(
                          iconSize: 16,
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () =>
                              setState(() => _rules.remove(draft)),
                        ),
                      ],
                    ),
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
                    child: Text('设置规则后点击预览，确认无冲突再执行',
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
