import 'package:flutter/material.dart';

import '../core/app_state.dart';
import 'widgets/activity_feed.dart';
import 'widgets/clock_widget.dart';
import 'widgets/pomodoro_widget.dart';
import 'widgets/system_monitor_tile.dart';
import 'widgets/todo_widget.dart';

/// Desktop dashboard with the persistent widgets (clock, pomodoro, todos,
/// activity feed), mirroring the original desktop workspace.
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key, required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          SizedBox(width: 320, child: ClockWidget(appState: appState)),
          SizedBox(width: 320, child: PomodoroWidget(appState: appState)),
          SizedBox(width: 320, child: TodoWidget(appState: appState)),
          const SizedBox(width: 320, child: SystemMonitorTile()),
          SizedBox(width: 320, child: ActivityFeed(appState: appState)),
        ],
      ),
    );
  }
}
