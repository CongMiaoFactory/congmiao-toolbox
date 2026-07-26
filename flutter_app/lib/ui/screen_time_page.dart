import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_services.dart';
import '../core/usage_tracker.dart';

/// Screen-time view backed by the foreground-window tracker (the Flutter
/// counterpart of `usage_tracker.rs` + ScreenTimeView.svelte). Tracking uses
/// win32 FFI, so live sampling is Windows-only for now.
class ScreenTimePage extends StatefulWidget {
  const ScreenTimePage({super.key});

  @override
  State<ScreenTimePage> createState() => _ScreenTimePageState();
}

class _ScreenTimePageState extends State<ScreenTimePage> {
  Timer? _timer;

  UsageTracker get tracker => AppServices.instance.usageTracker;

  @override
  void initState() {
    super.initState();
    tracker.start();
    _timer = Timer.periodic(
        const Duration(seconds: 2), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _format(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    if (hours > 0) return '$hours 小时 $minutes 分钟';
    if (minutes > 0) return '$minutes 分钟 $secs 秒';
    return '$secs 秒';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!tracker.supported) {
      return Center(
        child: Text(
          '前台窗口追踪目前仅支持 Windows（win32 FFI）。\n'
          'macOS / Linux 版本需要对应的平台探针，列入后续里程碑。',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
      );
    }
    final usage = tracker.appUsage();
    final total =
        usage.fold<int>(0, (sum, item) => sum + item.seconds);
    final top = usage.isEmpty ? 1 : usage.first.seconds;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('应用使用时长', style: theme.textTheme.titleMedium),
                const SizedBox(width: 12),
                Text('累计 ${_format(total)} · 每秒采样前台窗口',
                    style: theme.textTheme.labelSmall),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('清零'),
                  onPressed: () => setState(tracker.reset),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: usage.isEmpty
                  ? Center(
                      child: Text('正在统计…切换到其他应用后回来查看',
                          style: theme.textTheme.bodySmall),
                    )
                  : ListView.builder(
                      itemCount: usage.length,
                      itemBuilder: (context, index) {
                        final item = usage[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(item.appName,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodyMedium),
                                  ),
                                  Text(_format(item.seconds),
                                      style: theme.textTheme.labelMedium),
                                ],
                              ),
                              const SizedBox(height: 4),
                              LinearProgressIndicator(
                                value: item.seconds / top,
                                minHeight: 5,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
