import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../tools/actions.dart';

enum EncoderMode { base64, url, unicode }

/// Encoder window (EncoderTool.svelte): Base64 / URL / Unicode escapes in
/// both directions.
class EncoderTool extends StatefulWidget {
  const EncoderTool({super.key, required this.appState});

  final AppState appState;

  @override
  State<EncoderTool> createState() => _EncoderToolState();
}

class _EncoderToolState extends State<EncoderTool> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  EncoderMode _mode = EncoderMode.base64;
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  String _encodeUnicode(String text) {
    final buffer = StringBuffer();
    for (final unit in text.codeUnits) {
      if (unit > 0x7f) {
        buffer.write('\\u${unit.toRadixString(16).padLeft(4, '0')}');
      } else {
        buffer.writeCharCode(unit);
      }
    }
    return buffer.toString();
  }

  String _decodeUnicode(String text) {
    return text.replaceAllMapped(
      RegExp(r'\\u([0-9a-fA-F]{4})'),
      (match) => String.fromCharCode(int.parse(match.group(1)!, radix: 16)),
    );
  }

  void _run({required bool encode}) {
    final text = _input.text;
    if (text.isEmpty) {
      setState(() {
        _error = '请输入文本';
        _output.text = '';
      });
      return;
    }
    try {
      final String result;
      switch (_mode) {
        case EncoderMode.base64:
          result = encode
              ? base64Encode(utf8.encode(text))
              : utf8.decode(base64Decode(text.trim()));
        case EncoderMode.url:
          result = encode
              ? Uri.encodeComponent(text)
              : Uri.decodeComponent(text.trim());
        case EncoderMode.unicode:
          result = encode ? _encodeUnicode(text) : _decodeUnicode(text);
      }
      setState(() {
        _error = null;
        _output.text = result;
      });
      widget.appState.addActivity(
        source: 'TEXT',
        title: encode ? 'Encode' : 'Decode',
        value: '${_mode.name} · ${result.length} 字符',
      );
    } catch (_) {
      setState(() {
        _error = '转换失败，请检查输入内容与模式';
        _output.text = '';
      });
    }
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
              SegmentedButton<EncoderMode>(
                segments: const [
                  ButtonSegment(
                      value: EncoderMode.base64, label: Text('Base64')),
                  ButtonSegment(value: EncoderMode.url, label: Text('URL')),
                  ButtonSegment(
                      value: EncoderMode.unicode, label: Text('Unicode')),
                ],
                selected: {_mode},
                onSelectionChanged: (selection) =>
                    setState(() => _mode = selection.first),
              ),
              const Spacer(),
              FilledButton.tonal(
                onPressed: () => _run(encode: true),
                child: const Text('编码 ↓'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => _run(encode: false),
                child: const Text('解码 ↓'),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: '复制结果',
                icon: const Icon(Icons.copy, size: 18),
                onPressed: () async {
                  if (_output.text.isEmpty) return;
                  await copyText(_output.text);
                  widget.appState.addActivity(
                      source: 'TEXT', title: 'Encoder', value: '结果已复制');
                },
              ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(_error!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error)),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: TextField(
              controller: _input,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              decoration: const InputDecoration(
                hintText: '输入文本…',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: TextField(
              controller: _output,
              readOnly: true,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              decoration: const InputDecoration(
                hintText: '转换结果',
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
