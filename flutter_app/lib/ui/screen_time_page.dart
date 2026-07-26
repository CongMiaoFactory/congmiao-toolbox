import 'package:flutter/material.dart';

/// Placeholder for the screen-time view: the original relies on the Rust
/// `usage_tracker` module polling the foreground window. The Flutter port
/// will need a small platform channel per OS; documented in
/// docs/flutter-port.md.
class ScreenTimePage extends StatelessWidget {
  const ScreenTimePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.schedule, size: 48, color: theme.hintColor),
            const SizedBox(height: 16),
            Text('使用时长', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              '原版由 Rust usage_tracker 轮询前台窗口统计屏幕使用时间。\n'
              'Flutter 版需要为每个平台实现一个小型 MethodChannel（Windows: '
              'GetForegroundWindow，macOS: NSWorkspace），列入平台通道里程碑。',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
