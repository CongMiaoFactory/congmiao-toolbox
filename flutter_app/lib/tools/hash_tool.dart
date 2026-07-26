import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../tools/actions.dart';

/// Hash window (HashTool.svelte): MD5 / SHA-1 / SHA-256 / SHA-512 digests of
/// the input text. File hashing stays a follow-up (needs a file picker).
class HashTool extends StatefulWidget {
  const HashTool({super.key, required this.appState});

  final AppState appState;

  @override
  State<HashTool> createState() => _HashToolState();
}

class _HashToolState extends State<HashTool> {
  final TextEditingController _input = TextEditingController();
  Map<String, String> _digests = const {};

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _compute() {
    final text = _input.text;
    if (text.isEmpty) {
      setState(() => _digests = const {});
      return;
    }
    final bytes = utf8.encode(text);
    setState(() {
      _digests = {
        'MD5': md5.convert(bytes).toString(),
        'SHA-1': sha1.convert(bytes).toString(),
        'SHA-256': sha256.convert(bytes).toString(),
        'SHA-512': sha512.convert(bytes).toString(),
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 140,
            child: TextField(
              controller: _input,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              onChanged: (_) => _compute(),
              decoration: const InputDecoration(
                hintText: '输入要计算摘要的文本…',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _digests.isEmpty
                ? Center(
                    child: Text('输入文本后自动计算 MD5 与 SHA 系列摘要',
                        style: theme.textTheme.bodySmall),
                  )
                : ListView(
                    children: [
                      for (final entry in _digests.entries)
                        Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            dense: true,
                            title: Text(entry.key,
                                style: theme.textTheme.labelLarge),
                            subtitle: SelectableText(
                              entry.value,
                              style: theme.textTheme.bodySmall,
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.copy, size: 16),
                              onPressed: () async {
                                await copyText(entry.value);
                                widget.appState.addActivity(
                                  source: 'TEXT',
                                  title: 'Hash',
                                  value:
                                      '${entry.key} ${entry.value.substring(0, 12)}… 已复制',
                                );
                              },
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
