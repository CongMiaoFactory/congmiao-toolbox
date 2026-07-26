import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../core/app_state.dart';
import '../core/file_tools.dart' show formatBytes;
import '../core/tool_registry.dart';

/// Offline image converter (ImageConverterTool.svelte). The original used
/// the browser canvas; this port decodes with package:image (PNG/JPG/WebP/
/// GIF/BMP in) and encodes PNG or JPG. WebP encoding has no pure-Dart
/// encoder yet, so it stays input-only.
class ImageConverterTool extends StatefulWidget {
  const ImageConverterTool({super.key, required this.appState});

  final AppState appState;

  @override
  State<ImageConverterTool> createState() => _ImageConverterToolState();
}

class _ImageConverterToolState extends State<ImageConverterTool> {
  String? _sourcePath;
  Uint8List? _sourceBytes;
  img.Image? _decoded;
  String _format = 'png'; // png | jpg
  double _jpgQuality = 90;
  bool _busy = false;
  String? _message;
  bool _messageIsError = false;

  Future<void> _pick() async {
    const typeGroup = XTypeGroup(
      label: '图片',
      extensions: ['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp'],
    );
    final file = await openFile(acceptedTypeGroups: const [typeGroup]);
    if (file == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        setState(() {
          _message = '无法解码该图片格式';
          _messageIsError = true;
        });
        return;
      }
      setState(() {
        _sourcePath = file.path;
        _sourceBytes = bytes;
        _decoded = decoded;
        _message = null;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _convert() async {
    final decoded = _decoded;
    final sourcePath = _sourcePath;
    if (decoded == null || sourcePath == null || _busy) return;
    final suggested =
        '${p.basenameWithoutExtension(sourcePath)}.${_format == 'jpg' ? 'jpg' : 'png'}';
    final location = await getSaveLocation(
      suggestedName: suggested,
      acceptedTypeGroups: [
        XTypeGroup(label: _format.toUpperCase(), extensions: [_format]),
      ],
    );
    if (location == null) return;
    setState(() => _busy = true);
    try {
      final List<int> encoded = _format == 'jpg'
          ? img.encodeJpg(decoded, quality: _jpgQuality.round())
          : img.encodePng(decoded);
      await File(location.path).writeAsBytes(encoded, flush: true);
      setState(() {
        _message =
            '已保存 ${p.basename(location.path)} · ${formatBytes(encoded.length)}';
        _messageIsError = false;
      });
      widget.appState.addActivity(
        source: 'FILE',
        title: '图片格式工厂',
        value:
            '${p.basename(sourcePath)} → ${_format.toUpperCase()} (${formatBytes(encoded.length)})',
        accent: ToolAccent.orange,
      );
    } on FileSystemException catch (error) {
      setState(() {
        _message = '保存失败：${error.message}';
        _messageIsError = true;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final decoded = _decoded;
    final sourceBytes = _sourceBytes;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            FilledButton.tonalIcon(
              icon: const Icon(Icons.folder_open, size: 16),
              label: const Text('选择图片'),
              onPressed: _busy ? null : _pick,
            ),
            const SizedBox(width: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'png', label: Text('PNG')),
                ButtonSegment(value: 'jpg', label: Text('JPG')),
              ],
              selected: {_format},
              onSelectionChanged: (selection) =>
                  setState(() => _format = selection.first),
            ),
            if (_format == 'jpg') ...[
              const SizedBox(width: 12),
              const Text('质量'),
              SizedBox(
                width: 140,
                child: Slider(
                  value: _jpgQuality,
                  min: 10,
                  max: 100,
                  onChanged: (value) => setState(() => _jpgQuality = value),
                ),
              ),
              Text('${_jpgQuality.round()}'),
            ],
            const Spacer(),
            FilledButton.icon(
              icon: const Icon(Icons.save_alt, size: 16),
              label: Text(_busy ? '处理中…' : '转换并保存'),
              onPressed: decoded == null || _busy ? null : _convert,
            ),
          ]),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
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
            child: decoded == null || sourceBytes == null
                ? Center(
                    child: Text(
                      '选择 PNG / JPG / WebP / GIF / BMP 图片进行离线转换。\n'
                      '输出支持 PNG 与 JPG（WebP 目前只支持读取，纯 Dart 尚无编码器）。',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  )
                : Column(
                    children: [
                      Expanded(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(color: theme.dividerColor),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Image.memory(sourceBytes,
                                fit: BoxFit.contain,
                                gaplessPlayback: true),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${p.basename(_sourcePath!)} · ${decoded.width}×${decoded.height} · '
                        '${formatBytes(sourceBytes.length)}',
                        style: theme.textTheme.labelSmall,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
