import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/file_tools.dart' show formatBytes;
import '../../core/system_stats.dart';

/// Dashboard CPU / memory tile (SystemMonitorTile.svelte), fed by the shared
/// [SystemStatsService] sampler also used by the Peek server.
class SystemMonitorTile extends StatefulWidget {
  const SystemMonitorTile({super.key});

  @override
  State<SystemMonitorTile> createState() => _SystemMonitorTileState();
}

class _SystemMonitorTileState extends State<SystemMonitorTile> {
  Timer? _timer;
  SystemStats _stats = SystemStats.empty;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final stats = await AppServices.instance.systemStats.sample();
    if (mounted) setState(() => _stats = stats);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final memPercent = _stats.usedPercent / 100;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.monitor_heart_outlined,
                    size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('系统监控', style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 14),
            Row(children: [
              const SizedBox(width: 44, child: Text('CPU')),
              Expanded(
                child: LinearProgressIndicator(
                    value: (_stats.cpu / 100).clamp(0.0, 1.0)),
              ),
              SizedBox(
                width: 56,
                child: Text('${_stats.cpu.toStringAsFixed(0)}%',
                    textAlign: TextAlign.end),
              ),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              const SizedBox(width: 44, child: Text('内存')),
              Expanded(
                child: LinearProgressIndicator(
                    value: memPercent.clamp(0.0, 1.0).toDouble()),
              ),
              SizedBox(
                width: 56,
                child: Text('${_stats.usedPercent.toStringAsFixed(0)}%',
                    textAlign: TextAlign.end),
              ),
            ]),
            const SizedBox(height: 8),
            Text(
              _stats.totalMb <= 0
                  ? '正在采样…'
                  : '${formatBytes(_stats.usedMb * 1024 * 1024)} / ${formatBytes(_stats.totalMb * 1024 * 1024)}',
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}
