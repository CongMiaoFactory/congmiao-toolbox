import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/tool_registry.dart';
import '../../tools/actions.dart';

/// Desktop clock + unix timestamp tile (ClockWidget / TimestampTile).
class ClockWidget extends StatefulWidget {
  const ClockWidget({super.key, required this.appState});

  final AppState appState;

  @override
  State<ClockWidget> createState() => _ClockWidgetState();
}

class _ClockWidgetState extends State<ClockWidget> {
  late Timer _ticker;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  String _pad(int value) => value.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unix = _now.millisecondsSinceEpoch ~/ 1000;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.schedule,
                    size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('时钟', style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '${_pad(_now.hour)}:${_pad(_now.minute)}:${_pad(_now.second)}',
              style: theme.textTheme.displaySmall,
            ),
            const SizedBox(height: 4),
            Text(
              '${_now.year}-${_pad(_now.month)}-${_pad(_now.day)}',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text('Unix $unix',
                      style: theme.textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.copy, size: 14),
                  label: const Text('复制'),
                  onPressed: () async {
                    final copied = await copyText('$unix');
                    widget.appState.addActivity(
                      source: 'TEXT',
                      title: 'Timestamp Copied',
                      value: copied ? '$unix' : '复制失败',
                      accent: ToolAccent.teal,
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
