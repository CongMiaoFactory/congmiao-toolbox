import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_state.dart';

/// Pomodoro widget backed by the shared [TimerSnapshot], so a running cycle
/// survives restarts via `reconcileTimers` (PomodoroWidget.svelte).
class PomodoroWidget extends StatefulWidget {
  const PomodoroWidget({super.key, required this.appState});

  final AppState appState;

  @override
  State<PomodoroWidget> createState() => _PomodoroWidgetState();
}

class _PomodoroWidgetState extends State<PomodoroWidget> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _tick() {
    final pomodoro = widget.appState.timers.pomodoro;
    if (!pomodoro.running || pomodoro.targetAt == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now >= pomodoro.targetAt!) {
      var mode = pomodoro.mode;
      var target = pomodoro.targetAt!;
      while (target <= now) {
        mode = mode == 'work' ? 'break' : 'work';
        target += ((mode == 'work'
                    ? pomodoro.workSeconds
                    : pomodoro.breakSeconds) *
                1000)
            .round();
      }
      pomodoro.mode = mode;
      pomodoro.targetAt = target;
      pomodoro.remainingSeconds = ((target - now) / 1000).ceilToDouble();
      widget.appState.markTimersChanged();
      widget.appState.addActivity(
        source: 'SYSTEM',
        title: '番茄钟',
        value: mode == 'work' ? '休息结束，开始专注' : '专注结束，休息一下',
      );
    } else {
      setState(() {
        pomodoro.remainingSeconds =
            ((pomodoro.targetAt! - now) / 1000).ceilToDouble();
      });
    }
  }

  void _toggle() {
    final pomodoro = widget.appState.timers.pomodoro;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (pomodoro.running) {
      if (pomodoro.targetAt != null) {
        pomodoro.remainingSeconds =
            ((pomodoro.targetAt! - now) / 1000).clamp(0, double.infinity).ceilToDouble();
      }
      pomodoro.running = false;
      pomodoro.targetAt = null;
    } else {
      if (pomodoro.remainingSeconds <= 0) {
        pomodoro.remainingSeconds = pomodoro.mode == 'work'
            ? pomodoro.workSeconds
            : pomodoro.breakSeconds;
      }
      pomodoro.running = true;
      pomodoro.targetAt = now + (pomodoro.remainingSeconds * 1000).round();
    }
    widget.appState.markTimersChanged();
  }

  void _reset() {
    final pomodoro = widget.appState.timers.pomodoro;
    pomodoro.running = false;
    pomodoro.targetAt = null;
    pomodoro.mode = 'work';
    pomodoro.remainingSeconds = pomodoro.workSeconds;
    widget.appState.markTimersChanged();
  }

  String _format(double seconds) {
    final total = seconds.round();
    final minutes = (total ~/ 60).toString().padLeft(2, '0');
    final secs = (total % 60).toString().padLeft(2, '0');
    return '$minutes:$secs';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pomodoro = widget.appState.timers.pomodoro;
    final isWork = pomodoro.mode == 'work';
    final totalSeconds =
        isWork ? pomodoro.workSeconds : pomodoro.breakSeconds;
    final progress = totalSeconds <= 0
        ? 0.0
        : (1 - pomodoro.remainingSeconds / totalSeconds).clamp(0.0, 1.0);
    final accent = isWork
        ? theme.colorScheme.primary
        : const Color(0xFF4ADE80);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.local_cafe, size: 18, color: accent),
                const SizedBox(width: 8),
                Text('番茄钟', style: theme.textTheme.titleSmall),
                const Spacer(),
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(isWork ? '专注' : '休息'),
                  labelStyle: theme.textTheme.labelSmall,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                _format(pomodoro.remainingSeconds),
                style: theme.textTheme.displaySmall,
              ),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
                value: progress.toDouble(), color: accent),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.tonalIcon(
                  icon: Icon(
                      pomodoro.running ? Icons.pause : Icons.play_arrow,
                      size: 18),
                  label: Text(pomodoro.running ? '暂停' : '开始'),
                  onPressed: () => setState(_toggle),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('重置'),
                  onPressed: () => setState(_reset),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
