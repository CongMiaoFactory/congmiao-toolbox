import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../tools/actions.dart';

/// JSON formatter window (JsonFormatter.svelte): pretty-print, minify,
/// validate with an inline error message.
class JsonTool extends StatefulWidget {
  const JsonTool({super.key, required this.appState});

  final AppState appState;

  @override
  State<JsonTool> createState() => _JsonToolState();
}

class _JsonToolState extends State<JsonTool> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _run({required bool pretty}) {
    final text = _input.text.trim();
    if (text.isEmpty) {
      setState(() {
        _error = '请输入 JSON 文本';
        _output.text = '';
      });
      return;
    }
    try {
      final parsed = jsonDecode(text);
      setState(() {
        _error = null;
        _output.text = pretty
            ? const JsonEncoder.withIndent('  ').convert(parsed)
            : jsonEncode(parsed);
      });
      widget.appState.addActivity(
        source: 'TEXT',
        title: 'JSON Format',
        value: pretty ? '已格式化 ${_output.text.length} 字符' : '已压缩',
      );
    } on FormatException catch (error) {
      setState(() {
        _error = '解析失败：${error.message}';
        _output.text = '';
      });
    }
  }

  Future<void> _copyOutput() async {
    if (_output.text.isEmpty) return;
    final copied = await copyText(_output.text);
    widget.appState.addActivity(
      source: 'TEXT',
      title: 'JSON Format',
      value: copied ? '结果已复制' : '复制失败',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              FilledButton.tonalIcon(
                icon: const Icon(Icons.auto_awesome, size: 16),
                label: const Text('格式化'),
                onPressed: () => _run(pretty: true),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.compress, size: 16),
                label: const Text('压缩'),
                onPressed: () => _run(pretty: false),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('复制结果'),
                onPressed: _copyOutput,
              ),
              const Spacer(),
              TextButton(
                child: const Text('清空'),
                onPressed: () => setState(() {
                  _input.clear();
                  _output.clear();
                  _error = null;
                }),
              ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(Icons.error_outline,
                      size: 16, color: theme.colorScheme.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(_error!,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.error)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    style: theme.textTheme.bodySmall,
                    decoration: const InputDecoration(
                      hintText: '粘贴 JSON…',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _output,
                    readOnly: true,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    style: theme.textTheme.bodySmall,
                    decoration: const InputDecoration(
                      hintText: '输出结果',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
