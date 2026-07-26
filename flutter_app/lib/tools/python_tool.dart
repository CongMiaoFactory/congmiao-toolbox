import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/python_convert.dart';
import 'actions.dart';

/// Python toolbox window (PythonFormatter.svelte): dict → JSON conversion is
/// pure Dart; code formatting shells out to a locally installed `ruff`
/// (the original ran ruff-wasm inside the WebView, which has no Flutter
/// equivalent).
class PythonTool extends StatefulWidget {
  const PythonTool({super.key, required this.appState});

  final AppState appState;

  @override
  State<PythonTool> createState() => _PythonToolState();
}

class _PythonToolState extends State<PythonTool> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  bool _busy = false;
  String? _message;
  bool _messageIsError = false;

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _notify(String message, {bool isError = false}) {
    setState(() {
      _message = message;
      _messageIsError = isError;
    });
  }

  void _dictToJson() {
    final text = _input.text.trim();
    if (text.isEmpty) {
      _notify('请输入 Python 字典 / 列表字面量', isError: true);
      return;
    }
    try {
      final json = pythonLiteralToJson(text);
      setState(() => _output.text = json);
      _notify('已转换为 JSON');
      widget.appState.addActivity(
          source: 'TEXT', title: 'Python 工具集', value: '字典已转换为 JSON');
    } on PythonConvertException catch (error) {
      _notify('转换失败：${error.message}', isError: true);
    }
  }

  Future<void> _formatWithRuff() async {
    final code = _input.text;
    if (code.trim().isEmpty || _busy) {
      if (code.trim().isEmpty) _notify('请输入 Python 代码', isError: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final process = await Process.start(
          'ruff', ['format', '--stdin-filename', 'snippet.py', '-']);
      process.stdin.write(code);
      await process.stdin.close();
      final stdout = await process.stdout.transform(utf8.decoder).join();
      final stderr = await process.stderr.transform(utf8.decoder).join();
      final exitCode = await process.exitCode;
      if (exitCode != 0) {
        _notify('ruff 报错：${stderr.trim().isEmpty ? '退出码 $exitCode' : stderr.trim()}',
            isError: true);
        return;
      }
      setState(() => _output.text = stdout);
      _notify('已使用本机 ruff 排版');
      widget.appState.addActivity(
          source: 'TEXT', title: 'Python 工具集', value: 'ruff 排版完成');
    } on ProcessException {
      _notify('未检测到本机 ruff。安装后即可排版：pip install ruff', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            FilledButton.tonalIcon(
              icon: const Icon(Icons.data_object, size: 16),
              label: const Text('字典 → JSON'),
              onPressed: _dictToJson,
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.auto_fix_high, size: 16),
              label: Text(_busy ? '排版中…' : 'ruff 排版'),
              onPressed: _busy ? null : _formatWithRuff,
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('复制结果'),
              onPressed: () async {
                if (_output.text.isEmpty) return;
                await copyText(_output.text);
                _notify('结果已复制');
              },
            ),
            const Spacer(),
            TextButton(
              child: const Text('清空'),
              onPressed: () => setState(() {
                _input.clear();
                _output.clear();
                _message = null;
              }),
            ),
          ]),
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
          const SizedBox(height: 8),
          Expanded(
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  style: theme.textTheme.bodySmall,
                  decoration: const InputDecoration(
                    hintText: "粘贴 Python 代码或字典，如 {'name': '丛苗', 'tags': ('a', 1)}",
                    border: OutlineInputBorder(),
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
            ]),
          ),
        ],
      ),
    );
  }
}
