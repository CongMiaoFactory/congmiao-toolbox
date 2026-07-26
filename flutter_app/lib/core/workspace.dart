import 'dart:math' as math;

/// Mirror of `src/workspace.ts`: persisted workspace schema v1, timer
/// snapshots and the recovery/clamping helpers. The JSON layout is kept
/// compatible with the Tauri build's `workspace.json`.
const workspaceSchemaVersion = 1;
const defaultWallpaper =
    'https://images.unsplash.com/photo-1558591710-4b4a1ae0f04d?q=80&w=2574&auto=format&fit=crop';

double _asDouble(Object? value, [double fallback = 0]) {
  if (value is num && value.isFinite) return value.toDouble();
  return fallback;
}

int? _asNullableInt(Object? value) {
  if (value is num && value.isFinite) return value.toInt();
  return null;
}

class TodoItem {
  TodoItem({required this.id, required this.text, required this.done});

  factory TodoItem.fromJson(Map<String, dynamic> json) => TodoItem(
        id: json['id'] as String? ?? '',
        text: json['text'] as String? ?? '',
        done: json['done'] as bool? ?? false,
      );

  final String id;
  String text;
  bool done;

  Map<String, dynamic> toJson() => {'id': id, 'text': text, 'done': done};
}

class WindowGeometry {
  const WindowGeometry({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  factory WindowGeometry.fromJson(Map<String, dynamic> json) => WindowGeometry(
        x: _asDouble(json['x']),
        y: _asDouble(json['y']),
        width: _asDouble(json['width']),
        height: _asDouble(json['height']),
      );

  final double x;
  final double y;
  final double width;
  final double height;

  Map<String, dynamic> toJson() =>
      {'x': x, 'y': y, 'width': width, 'height': height};
}

class PersistedWindow {
  PersistedWindow({
    required this.id,
    required this.toolId,
    required this.geometry,
    required this.zIndex,
    required this.isMinimized,
    required this.isMaximized,
    this.restoreGeometry,
  });

  factory PersistedWindow.fromJson(Map<String, dynamic> json) =>
      PersistedWindow(
        id: json['id'] as String? ?? '',
        toolId: json['toolId'] as String? ?? '',
        geometry: WindowGeometry.fromJson(json),
        zIndex: _asNullableInt(json['zIndex']) ?? 9,
        isMinimized: json['isMinimized'] as bool? ?? false,
        isMaximized: json['isMaximized'] as bool? ?? false,
        restoreGeometry: json['restoreGeometry'] is Map<String, dynamic>
            ? WindowGeometry.fromJson(
                json['restoreGeometry'] as Map<String, dynamic>)
            : null,
      );

  final String id;
  final String toolId;
  final WindowGeometry geometry;
  final int zIndex;
  final bool isMinimized;
  final bool isMaximized;
  final WindowGeometry? restoreGeometry;

  Map<String, dynamic> toJson() => {
        ...geometry.toJson(),
        'id': id,
        'toolId': toolId,
        'zIndex': zIndex,
        'isMinimized': isMinimized,
        'isMaximized': isMaximized,
        'restoreGeometry': restoreGeometry?.toJson(),
      };
}

class StopwatchSnapshot {
  StopwatchSnapshot({
    required this.elapsedMs,
    required this.running,
    required this.startedAt,
    required this.laps,
  });

  factory StopwatchSnapshot.fromJson(Map<String, dynamic> json) =>
      StopwatchSnapshot(
        elapsedMs: _asDouble(json['elapsedMs']),
        running: json['running'] as bool? ?? false,
        startedAt: _asNullableInt(json['startedAt']),
        laps: json['laps'] is List
            ? (json['laps'] as List)
                .whereType<num>()
                .map((lap) => lap.toDouble())
                .toList()
            : <double>[],
      );

  double elapsedMs;
  bool running;
  int? startedAt;
  List<double> laps;

  Map<String, dynamic> toJson() => {
        'elapsedMs': elapsedMs,
        'running': running,
        'startedAt': startedAt,
        'laps': laps,
      };

  StopwatchSnapshot copy() => StopwatchSnapshot(
        elapsedMs: elapsedMs,
        running: running,
        startedAt: startedAt,
        laps: List.of(laps),
      );
}

class CountdownSnapshot {
  CountdownSnapshot({
    required this.inputMinutes,
    required this.totalMs,
    required this.remainingMs,
    required this.running,
    required this.targetAt,
  });

  factory CountdownSnapshot.fromJson(Map<String, dynamic> json) =>
      CountdownSnapshot(
        inputMinutes: _asDouble(json['inputMinutes'], 5),
        totalMs: _asDouble(json['totalMs']),
        remainingMs: _asDouble(json['remainingMs']),
        running: json['running'] as bool? ?? false,
        targetAt: _asNullableInt(json['targetAt']),
      );

  double inputMinutes;
  double totalMs;
  double remainingMs;
  bool running;
  int? targetAt;

  Map<String, dynamic> toJson() => {
        'inputMinutes': inputMinutes,
        'totalMs': totalMs,
        'remainingMs': remainingMs,
        'running': running,
        'targetAt': targetAt,
      };

  CountdownSnapshot copy() => CountdownSnapshot(
        inputMinutes: inputMinutes,
        totalMs: totalMs,
        remainingMs: remainingMs,
        running: running,
        targetAt: targetAt,
      );
}

class PomodoroSnapshot {
  PomodoroSnapshot({
    required this.mode,
    required this.workSeconds,
    required this.breakSeconds,
    required this.remainingSeconds,
    required this.running,
    required this.targetAt,
  });

  factory PomodoroSnapshot.fromJson(Map<String, dynamic> json) =>
      PomodoroSnapshot(
        mode: json['mode'] == 'break' ? 'break' : 'work',
        workSeconds: _asDouble(json['workSeconds'], 1500),
        breakSeconds: _asDouble(json['breakSeconds'], 300),
        remainingSeconds: _asDouble(json['remainingSeconds']),
        running: json['running'] as bool? ?? false,
        targetAt: _asNullableInt(json['targetAt']),
      );

  String mode;
  double workSeconds;
  double breakSeconds;
  double remainingSeconds;
  bool running;
  int? targetAt;

  Map<String, dynamic> toJson() => {
        'mode': mode,
        'workSeconds': workSeconds,
        'breakSeconds': breakSeconds,
        'remainingSeconds': remainingSeconds,
        'running': running,
        'targetAt': targetAt,
      };

  PomodoroSnapshot copy() => PomodoroSnapshot(
        mode: mode,
        workSeconds: workSeconds,
        breakSeconds: breakSeconds,
        remainingSeconds: remainingSeconds,
        running: running,
        targetAt: targetAt,
      );
}

class TimerSnapshot {
  TimerSnapshot({
    required this.selectedMode,
    required this.stopwatch,
    required this.countdown,
    required this.pomodoro,
  });

  factory TimerSnapshot.fromJson(Map<String, dynamic> json) => TimerSnapshot(
        selectedMode:
            json['selectedMode'] == 'countdown' ? 'countdown' : 'stopwatch',
        stopwatch: json['stopwatch'] is Map<String, dynamic>
            ? StopwatchSnapshot.fromJson(
                json['stopwatch'] as Map<String, dynamic>)
            : defaultTimerSnapshot().stopwatch,
        countdown: json['countdown'] is Map<String, dynamic>
            ? CountdownSnapshot.fromJson(
                json['countdown'] as Map<String, dynamic>)
            : defaultTimerSnapshot().countdown,
        pomodoro: json['pomodoro'] is Map<String, dynamic>
            ? PomodoroSnapshot.fromJson(json['pomodoro'] as Map<String, dynamic>)
            : defaultTimerSnapshot().pomodoro,
      );

  String selectedMode;
  StopwatchSnapshot stopwatch;
  CountdownSnapshot countdown;
  PomodoroSnapshot pomodoro;

  Map<String, dynamic> toJson() => {
        'selectedMode': selectedMode,
        'stopwatch': stopwatch.toJson(),
        'countdown': countdown.toJson(),
        'pomodoro': pomodoro.toJson(),
      };

  TimerSnapshot copy() => TimerSnapshot(
        selectedMode: selectedMode,
        stopwatch: stopwatch.copy(),
        countdown: countdown.copy(),
        pomodoro: pomodoro.copy(),
      );
}

class WorkspacePreferences {
  WorkspacePreferences({
    required this.theme,
    required this.bgImageUrl,
    required this.bgBlur,
    required this.sidebarCollapsed,
  });

  factory WorkspacePreferences.fromJson(Map<String, dynamic> json) =>
      WorkspacePreferences(
        theme: json['theme'] == 'dark' ? 'dark' : 'light',
        bgImageUrl: json['bgImageUrl'] as String? ?? defaultWallpaper,
        bgBlur: _asDouble(json['bgBlur']).clamp(0, 100).toDouble(),
        sidebarCollapsed: json['sidebarCollapsed'] as bool? ?? true,
      );

  String theme;
  String bgImageUrl;
  double bgBlur;
  bool sidebarCollapsed;

  Map<String, dynamic> toJson() => {
        'theme': theme,
        'bgImageUrl': bgImageUrl,
        'bgBlur': bgBlur,
        'sidebarCollapsed': sidebarCollapsed,
      };
}

class WorkspaceDesktop {
  WorkspaceDesktop({
    required this.activeNavIndex,
    required this.activeWindowId,
    required this.windows,
  });

  factory WorkspaceDesktop.fromJson(Map<String, dynamic> json) =>
      WorkspaceDesktop(
        activeNavIndex: _asNullableInt(json['activeNavIndex']) ?? 0,
        activeWindowId: json['activeWindowId'] as String?,
        windows: json['windows'] is List
            ? (json['windows'] as List)
                .whereType<Map<String, dynamic>>()
                .map(PersistedWindow.fromJson)
                .toList()
            : <PersistedWindow>[],
      );

  int activeNavIndex;
  String? activeWindowId;
  List<PersistedWindow> windows;

  Map<String, dynamic> toJson() => {
        'activeNavIndex': activeNavIndex,
        'activeWindowId': activeWindowId,
        'windows': windows.map((window) => window.toJson()).toList(),
      };
}

class WorkspaceTemplate {
  WorkspaceTemplate({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.preferences,
    required this.desktop,
    required this.timers,
  });

  factory WorkspaceTemplate.fromJson(Map<String, dynamic> json) =>
      WorkspaceTemplate(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        createdAt: _asNullableInt(json['createdAt']) ?? 0,
        updatedAt: _asNullableInt(json['updatedAt']) ?? 0,
        preferences: WorkspacePreferences.fromJson(
            json['preferences'] as Map<String, dynamic>? ?? const {}),
        desktop: WorkspaceDesktop.fromJson(
            json['desktop'] as Map<String, dynamic>? ?? const {}),
        timers: TimerSnapshot.fromJson(
            json['timers'] as Map<String, dynamic>? ?? const {}),
      );

  final String id;
  String name;
  final int createdAt;
  int updatedAt;
  WorkspacePreferences preferences;
  WorkspaceDesktop desktop;
  TimerSnapshot timers;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'preferences': preferences.toJson(),
        'desktop': desktop.toJson(),
        'timers': timers.toJson(),
      };
}

class RecentToolUsage {
  RecentToolUsage({
    required this.id,
    required this.lastUsedAt,
    required this.useCount,
  });

  factory RecentToolUsage.fromJson(Map<String, dynamic> json) =>
      RecentToolUsage(
        id: json['id'] as String? ?? '',
        lastUsedAt: _asNullableInt(json['lastUsedAt']) ?? 0,
        useCount: _asNullableInt(json['useCount']) ?? 0,
      );

  final String id;
  int lastUsedAt;
  int useCount;

  Map<String, dynamic> toJson() =>
      {'id': id, 'lastUsedAt': lastUsedAt, 'useCount': useCount};
}

class LauncherPreferences {
  LauncherPreferences({
    required this.favorites,
    required this.recentTools,
    required this.globalShortcut,
  });

  factory LauncherPreferences.fromJson(Map<String, dynamic> json) =>
      LauncherPreferences(
        favorites: json['favorites'] is List
            ? (json['favorites'] as List).whereType<String>().toList()
            : <String>[],
        recentTools: json['recentTools'] is List
            ? (json['recentTools'] as List)
                .whereType<Map<String, dynamic>>()
                .map(RecentToolUsage.fromJson)
                .toList()
            : <RecentToolUsage>[],
        globalShortcut:
            json['globalShortcut'] as String? ?? 'Ctrl+Alt+Space',
      );

  List<String> favorites;
  List<RecentToolUsage> recentTools;
  String globalShortcut;

  Map<String, dynamic> toJson() => {
        'favorites': favorites,
        'recentTools': recentTools.map((item) => item.toJson()).toList(),
        'globalShortcut': globalShortcut,
      };
}

class PersistedWorkspace {
  PersistedWorkspace({
    required this.savedAt,
    required this.preferences,
    required this.desktop,
    required this.todos,
    required this.timers,
    required this.workspaceTemplates,
    required this.launcher,
  });

  factory PersistedWorkspace.fromJson(Map<String, dynamic> json) =>
      PersistedWorkspace(
        savedAt: _asNullableInt(json['savedAt']) ?? 0,
        preferences: WorkspacePreferences.fromJson(
            json['preferences'] as Map<String, dynamic>? ?? const {}),
        desktop: WorkspaceDesktop.fromJson(
            json['desktop'] as Map<String, dynamic>? ?? const {}),
        todos: json['todos'] is List
            ? (json['todos'] as List)
                .whereType<Map<String, dynamic>>()
                .map(TodoItem.fromJson)
                .toList()
            : <TodoItem>[],
        timers: TimerSnapshot.fromJson(
            json['timers'] as Map<String, dynamic>? ?? const {}),
        workspaceTemplates: json['workspaceTemplates'] is List
            ? (json['workspaceTemplates'] as List)
                .whereType<Map<String, dynamic>>()
                .map(WorkspaceTemplate.fromJson)
                .toList()
            : <WorkspaceTemplate>[],
        launcher: json['launcher'] is Map<String, dynamic>
            ? LauncherPreferences.fromJson(
                json['launcher'] as Map<String, dynamic>)
            : LauncherPreferences.fromJson(const {}),
      );

  final int savedAt;
  final WorkspacePreferences preferences;
  final WorkspaceDesktop desktop;
  final List<TodoItem> todos;
  final TimerSnapshot timers;
  final List<WorkspaceTemplate> workspaceTemplates;
  final LauncherPreferences launcher;

  Map<String, dynamic> toJson() => {
        'schemaVersion': workspaceSchemaVersion,
        'savedAt': savedAt,
        'preferences': preferences.toJson(),
        'desktop': desktop.toJson(),
        'todos': todos.map((todo) => todo.toJson()).toList(),
        'timers': timers.toJson(),
        'workspaceTemplates':
            workspaceTemplates.map((template) => template.toJson()).toList(),
        'launcher': launcher.toJson(),
      };
}

LauncherPreferences defaultLauncherPreferences() =>
    LauncherPreferences.fromJson(const {});

TimerSnapshot defaultTimerSnapshot() => TimerSnapshot(
      selectedMode: 'stopwatch',
      stopwatch: StopwatchSnapshot(
          elapsedMs: 0, running: false, startedAt: null, laps: []),
      countdown: CountdownSnapshot(
        inputMinutes: 5,
        totalMs: 300000,
        remainingMs: 300000,
        running: false,
        targetAt: null,
      ),
      pomodoro: PomodoroSnapshot(
        mode: 'work',
        workSeconds: 1500,
        breakSeconds: 300,
        remainingSeconds: 1500,
        running: false,
        targetAt: null,
      ),
    );

/// Deep-copies a snapshot with live targets cleared, matching `timerPreset`.
TimerSnapshot timerPreset(TimerSnapshot snapshot) {
  final timers = snapshot.copy();
  timers.stopwatch.running = false;
  timers.stopwatch.startedAt = null;
  timers.countdown.running = false;
  timers.countdown.targetAt = null;
  timers.pomodoro.running = false;
  timers.pomodoro.targetAt = null;
  return timers;
}

class Viewport {
  const Viewport({required this.width, required this.height});

  final double width;
  final double height;
}

WindowGeometry clampGeometry(
  WindowGeometry geometry,
  Viewport viewport, {
  required double minWidth,
  required double minHeight,
}) {
  final width = math.min(
      math.max(geometry.width, minWidth), math.max(minWidth, viewport.width));
  final height = math.min(math.max(geometry.height, minHeight),
      math.max(minHeight, viewport.height));
  return WindowGeometry(
    x: math.min(
        math.max(geometry.x, 0.0), math.max(0.0, viewport.width - width)),
    y: math.min(
        math.max(geometry.y, 0.0), math.max(0.0, viewport.height - height)),
    width: width,
    height: height,
  );
}

/// Recovers persisted timers against wall-clock time, matching
/// `reconcileTimers` in the original app.
TimerSnapshot reconcileTimers(TimerSnapshot snapshot, {int? now}) {
  final nowMs = now ?? DateTime.now().millisecondsSinceEpoch;
  final timers = snapshot.copy();

  final stopwatch = timers.stopwatch;
  stopwatch.elapsedMs = math.max(0.0, stopwatch.elapsedMs);
  stopwatch.laps =
      stopwatch.laps.where((lap) => lap.isFinite && lap >= 0).take(100).toList();
  if (stopwatch.running &&
      stopwatch.startedAt != null &&
      stopwatch.startedAt! > nowMs) {
    stopwatch.startedAt = nowMs;
  }

  final countdown = timers.countdown;
  countdown.inputMinutes = (countdown.inputMinutes == 0
          ? 5.0
          : countdown.inputMinutes)
      .clamp(1, 1440)
      .toDouble();
  countdown.totalMs = math.max(
      0.0,
      countdown.totalMs == 0
          ? countdown.inputMinutes * 60000
          : countdown.totalMs);
  countdown.remainingMs = math.max(0.0, countdown.remainingMs);
  if (countdown.running && countdown.targetAt != null) {
    countdown.remainingMs =
        math.max(0.0, (countdown.targetAt! - nowMs).toDouble());
    if (countdown.remainingMs == 0) {
      countdown.running = false;
      countdown.targetAt = null;
    }
  }

  final pomodoro = timers.pomodoro;
  pomodoro.mode = pomodoro.mode == 'break' ? 'break' : 'work';
  pomodoro.workSeconds = math.max(
      60.0, pomodoro.workSeconds == 0 ? 1500.0 : pomodoro.workSeconds);
  pomodoro.breakSeconds = math.max(
      60.0, pomodoro.breakSeconds == 0 ? 300.0 : pomodoro.breakSeconds);
  pomodoro.remainingSeconds = math.max(0.0, pomodoro.remainingSeconds);
  if (pomodoro.running && pomodoro.targetAt != null) {
    var target = pomodoro.targetAt!;
    var mode = pomodoro.mode;
    while (target <= nowMs) {
      mode = mode == 'work' ? 'break' : 'work';
      target += ((mode == 'work' ? pomodoro.workSeconds : pomodoro.breakSeconds) *
              1000)
          .round();
    }
    pomodoro.mode = mode;
    pomodoro.targetAt = target;
    pomodoro.remainingSeconds =
        math.max(0, ((target - nowMs) / 1000).ceil()).toDouble();
  }
  return timers;
}

/// Structural validation matching `isWorkspaceV1`.
bool isWorkspaceV1(Object? value) {
  if (value is! Map<String, dynamic>) return false;
  final preferences = value['preferences'];
  final desktop = value['desktop'];
  final timers = value['timers'];
  return value['schemaVersion'] == workspaceSchemaVersion &&
      preferences is Map<String, dynamic> &&
      (preferences['theme'] == 'dark' || preferences['theme'] == 'light') &&
      preferences['bgImageUrl'] is String &&
      preferences['bgBlur'] is num &&
      preferences['sidebarCollapsed'] is bool &&
      desktop is Map<String, dynamic> &&
      desktop['activeNavIndex'] is num &&
      desktop['windows'] is List &&
      value['todos'] is List &&
      timers is Map<String, dynamic> &&
      timers['stopwatch'] is Map<String, dynamic> &&
      timers['countdown'] is Map<String, dynamic> &&
      timers['pomodoro'] is Map<String, dynamic>;
}
