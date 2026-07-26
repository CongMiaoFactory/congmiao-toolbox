import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import 'actions.dart';

/// Translator window (TranslatorTool.svelte): same free Google endpoint
/// (`translate_a/single?client=gtx`), common language pairs and swap.
const _languages = <(String, String)>[
  ('auto', '自动检测'),
  ('zh-CN', '中文（简体）'),
  ('zh-TW', '中文（繁体）'),
  ('en', 'English'),
  ('ja', '日本語'),
  ('ko', '한국어'),
  ('fr', 'Français'),
  ('de', 'Deutsch'),
  ('es', 'Español'),
  ('ru', 'Русский'),
];

Future<String> translateText(
    String text, String sourceLang, String targetLang) async {
  final uri = Uri.parse(
      'https://translate.googleapis.com/translate_a/single?client=gtx'
      '&sl=$sourceLang&tl=$targetLang&dt=t&q=${Uri.encodeComponent(text)}');
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
  try {
    final request = await client.getUrl(uri);
    final response = await request.close();
    if (response.statusCode != 200) {
      throw HttpException('请求失败 ${response.statusCode}');
    }
    final body = await response.transform(utf8.decoder).join();
    final decoded = jsonDecode(body);
    if (decoded is! List || decoded.isEmpty || decoded.first is! List) {
      throw const FormatException('响应格式不符合预期');
    }
    final buffer = StringBuffer();
    for (final segment in decoded.first as List) {
      if (segment is List && segment.isNotEmpty && segment.first is String) {
        buffer.write(segment.first as String);
      }
    }
    return buffer.toString();
  } finally {
    client.close(force: true);
  }
}

class TranslatorTool extends StatefulWidget {
  const TranslatorTool({super.key, required this.appState});

  final AppState appState;

  @override
  State<TranslatorTool> createState() => _TranslatorToolState();
}

class _TranslatorToolState extends State<TranslatorTool> {
  final TextEditingController _source = TextEditingController();
  final TextEditingController _target = TextEditingController();
  String _sourceLang = 'auto';
  String _targetLang = 'zh-CN';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _source.dispose();
    _target.dispose();
    super.dispose();
  }

  Future<void> _translate() async {
    final text = _source.text.trim();
    if (text.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await translateText(text, _sourceLang, _targetLang);
      if (!mounted) return;
      setState(() => _target.text = result);
      widget.appState.addActivity(
          source: 'TEXT', title: '翻译机', value: '已翻译 ${text.length} 字符');
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '翻译失败：$error（需要联网，接口在部分网络环境不可用）');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _swap() {
    setState(() {
      final lang = _sourceLang == 'auto' ? _targetLang : _sourceLang;
      _sourceLang = _targetLang;
      _targetLang = lang == _targetLang ? 'en' : lang;
      final text = _source.text;
      _source.text = _target.text;
      _target.text = text;
    });
  }

  DropdownButton<String> _langPicker(
      String value, bool allowAuto, ValueChanged<String> onChanged) {
    return DropdownButton<String>(
      value: value,
      items: [
        for (final (code, label) in _languages)
          if (allowAuto || code != 'auto')
            DropdownMenuItem(value: code, child: Text(label)),
      ],
      onChanged: (next) {
        if (next != null) onChanged(next);
      },
    );
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
            _langPicker(_sourceLang, true,
                (value) => setState(() => _sourceLang = value)),
            IconButton(
              tooltip: '交换语言',
              icon: const Icon(Icons.swap_horiz),
              onPressed: _swap,
            ),
            _langPicker(_targetLang, false,
                (value) => setState(() => _targetLang = value)),
            const Spacer(),
            FilledButton.icon(
              icon: _busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.translate, size: 16),
              label: Text(_busy ? '翻译中…' : '翻译'),
              onPressed: _busy ? null : _translate,
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('复制结果'),
              onPressed: () async {
                if (_target.text.isEmpty) return;
                await copyText(_target.text);
                widget.appState.addActivity(
                    source: 'TEXT', title: '翻译机', value: '结果已复制');
              },
            ),
          ]),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(_error!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error)),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: TextField(
              controller: _source,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              decoration: const InputDecoration(
                hintText: '输入要翻译的文本…',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: TextField(
              controller: _target,
              readOnly: true,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              decoration: const InputDecoration(
                hintText: '翻译结果（免费接口，需联网）',
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
