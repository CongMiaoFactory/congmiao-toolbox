import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_state.dart';

/// Productivity clock window (TimerTool.svelte): stopwatch with laps and a
/// countdown, both stored in the shared [TimerSnapshot] so running timers
/// survive an app restart through `reconcileTimers`.
class TimerTool extends StatefulWidget {
  const TimerTool({super.key, required this.appState});

  final AppState appState;

  @override
  State<TimerTool> createState() => _TimerToolState();
}

class _TimerToolState extends State<TimerTool> {
  Timer? _ticker;
  final TextEditingController _minutesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _minutesController.text = widget
        .appState.timers.countdown.inputMinutes
        .round()
        .toString();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final timers = widget.appState.timers;
      if (timers.stopwatch.running || timers.countdown.running) {
        setState(() => _syncCountdown());
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _minutesController.dispose();
    super.dispose();
  }

  int get _nowMs => DateTime.now().millisecondsSinceEpoch;

  double get _stopwatchElapsed {
    final stopwatch = widget.appState.timers.stopwatch;
    if (stopwatch.running && stopwatch.startedAt != null) {
      return stopwatch.elapsedMs + (_nowMs - stopwatch.startedAt!);
    }
    return stopwatch.elapsedMs;
  }

  void _syncCountdown() {
    final countdown = widget.appState.timers.countdown;
    if (!countdown.running || countdown.targetAt == null) return;
    final remaining = countdown.targetAt! - _nowMs;
    if (remaining <= 0) {
      countdown.remainingMs = 0;
      countdown.running = false;
      countdown.targetAt = null;
      widget.appState.markTimersChanged();
      widget.appState.addActivity(
          source: 'SYSTEM', title: '倒计时', value: '倒计时结束');
    } else {
      countdown.remainingMs = remaining.toDouble();
    }
  }

  void _toggleStopwatch() {
    final stopwatch = widget.appState.timers.stopwatch;
    if (stopwatch.running) {
      stopwatch.elapsedMs = _stopwatchElapsed;
      stopwatch.running = false;
      stopwatch.startedAt = null;
    } else {
      stopwatch.running = true;
      stopwatch.startedAt = _nowMs;
    }
    widget.appState.markTimersChanged();
    setState(() {});
  }

  void _lapStopwatch() {
    final stopwatch = widget.appState.timers.stopwatch;
    if (!stopwatch.running) return;
    if (stopwatch.laps.length >= 100) return;
    stopwatch.laps.insert(0, _stopwatchElapsed);
    widget.appState.markTimersChanged();
    setState(() {});
  }

  void _resetStopwatch() {
    final stopwatch = widget.appState.timers.stopwatch;
    stopwatch.running = false;
    stopwatch.startedAt = null;
    stopwatch.elapsedMs = 0;
    stopwatch.laps.clear();
    widget.appState.markTimersChanged();
    setState(() {});
  }

  void _toggleCountdown() {
    final countdown = widget.appState.timers.countdown;
    if (countdown.running) {
      _syncCountdown();
      countdown.running = false;
      countdown.targetAt = null;
    } else {
      final minutes =
          double.tryParse(_minutesController.text.trim()) ?? countdown.inputMinutes;
      final clamped = minutes.clamp(1, 1440).toDouble();
      if (countdown.remainingMs <= 0 ||
          clamped.round() != countdown.inputMinutes.round()) {
        countdown.inputMinutes = clamped;
        countdown.totalMs = clamped * 60000;
        countdown.remainingMs = countdown.totalMs;
      }
      countdown.running = true;
      countdown.targetAt = _nowMs + countdown.remainingMs.round();
    }
    widget.appState.markTimersChanged();
    setState(() {});
  }

  void _resetCountdown() {
    final countdown = widget.appState.timers.countdown;
    countdown.running = false;
    countdown.targetAt = null;
    countdown.remainingMs = countdown.totalMs;
    widget.appState.markTimersChanged();
    setState(() {});
  }

  String _formatMs(double milliseconds, {bool centis = true}) {
    final total = milliseconds.round();
    final minutes = total ~/ 60000;
    final seconds = (total % 60000) ~/ 1000;
    final centiseconds = (total % 1000) ~/ 10;
    final base =
        '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    return centis
        ? '$base.${centiseconds.toString().padLeft(2, '0')}'
        : base;
  }

  Widget _buildStopwatch(BuildContext context) {
    final theme = Theme.of(context);
    final stopwatch = widget.appState.timers.stopwatch;
    return Column(
      children: [
        const SizedBox(height: 16),
        Text(_formatMs(_stopwatchElapsed),
            style: theme.textTheme.displayMedium),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FilledButton.icon(
              icon: Icon(stopwatch.running ? Icons.pause : Icons.play_arrow),
              label: Text(stopwatch.running ? '暂停' : '开始'),
              onPressed: _toggleStopwatch,
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.flag),
              label: const Text('计圈'),
              onPressed: stopwatch.running ? _lapStopwatch : null,
            ),
            const SizedBox(width: 12),
            TextButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('重置'),
              onPressed: _resetStopwatch,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: stopwatch.laps.isEmpty
              ? Center(
                  child:
                      Text('暂无计圈', style: theme.textTheme.bodySmall))
              : ListView.builder(
                  itemCount: stopwatch.laps.length,
                  itemBuilder: (context, index) {
                    final lap = stopwatch.laps[index];
                    final number = stopwatch.laps.length - index;
                    return ListTile(
                      dense: true,
                      leading: Text('#$number'),
                      title: Text(_formatMs(lap)),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildCountdown(BuildContext context) {
    final theme = Theme.of(context);
    final countdown = widget.appState.timers.countdown;
    final progress = countdown.totalMs <= 0
        ? 0.0
        : (1 - countdown.remainingMs / countdown.totalMs).clamp(0.0, 1.0);
    return Column(
      children: [
        const SizedBox(height: 16),
        Text(_formatMs(countdown.remainingMs, centis: false),
            style: theme.textTheme.displayMedium),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48),
          child: LinearProgressIndicator(value: progress.toDouble()),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 120,
              child: TextField(
                controller: _minutesController,
                keyboardType: TextInputType.number,
                enabled: !countdown.running,
                decoration: const InputDecoration(
                  labelText: '分钟',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              icon: Icon(countdown.running ? Icons.pause : Icons.play_arrow),
              label: Text(countdown.running ? '暂停' : '开始'),
              onPressed: _toggleCountdown,
            ),
            const SizedBox(width: 12),
            TextButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('重置'),
              onPressed: _resetCountdown,
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final timers = widget.appState.timers;
    final selectedCountdown = timers.selectedMode == 'countdown';
    return Column(
      children: [
        const SizedBox(height: 12),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'stopwatch', label: Text('秒表')),
            ButtonSegment(value: 'countdown', label: Text('倒计时')),
          ],
          selected: {timers.selectedMode},
          onSelectionChanged: (selection) {
            timers.selectedMode = selection.first;
            widget.appState.markTimersChanged();
            setState(() {});
          },
        ),
        Expanded(
          child: selectedCountdown
              ? _buildCountdown(context)
              : _buildStopwatch(context),
        ),
      ],
    );
  }
}
