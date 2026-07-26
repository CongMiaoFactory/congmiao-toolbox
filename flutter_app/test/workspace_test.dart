import 'package:congmiao_toolbox_flutter/core/tool_registry.dart';
import 'package:congmiao_toolbox_flutter/core/workspace.dart';
import 'package:congmiao_toolbox_flutter/tools/tool_windows.dart';
import 'package:flutter_test/flutter_test.dart';

/// Dart port of `src/workspace.test.ts`.
void main() {
  group('workspace geometry', () {
    test('clamps restored windows into the visible desktop', () {
      final clamped = clampGeometry(
        const WindowGeometry(x: 1800, y: -100, width: 1200, height: 900),
        const Viewport(width: 1000, height: 700),
        minWidth: 500,
        minHeight: 400,
      );
      expect(clamped.x, 0);
      expect(clamped.y, 0);
      expect(clamped.width, 1000);
      expect(clamped.height, 700);
    });
  });

  group('timer recovery', () {
    test('finishes an expired countdown', () {
      final timers = defaultTimerSnapshot();
      timers.countdown.running = true;
      timers.countdown.targetAt = 9000;
      final restored = reconcileTimers(timers, now: 10000);
      expect(restored.countdown.running, isFalse);
      expect(restored.countdown.remainingMs, 0);
      expect(restored.countdown.targetAt, isNull);
    });

    test('advances pomodoro cycles using real elapsed time', () {
      final timers = defaultTimerSnapshot();
      timers.pomodoro = PomodoroSnapshot(
        mode: 'work',
        workSeconds: 60,
        breakSeconds: 60,
        remainingSeconds: 1,
        running: true,
        targetAt: 1000,
      );
      final restored = reconcileTimers(timers, now: 70000);
      expect(restored.pomodoro.mode, 'work');
      expect(restored.pomodoro.targetAt, 121000);
      expect(restored.pomodoro.remainingSeconds, 51);
    });

    test('stores timer presets without live targets', () {
      final timers = defaultTimerSnapshot();
      timers.countdown.running = true;
      timers.countdown.targetAt = 12345;
      timers.pomodoro.running = true;
      timers.pomodoro.targetAt = 67890;
      final preset = timerPreset(timers);
      expect(preset.countdown.running, isFalse);
      expect(preset.countdown.targetAt, isNull);
      expect(preset.pomodoro.running, isFalse);
      expect(preset.pomodoro.targetAt, isNull);
    });
  });

  group('workspace schema and tool registry', () {
    test('rejects malformed workspace data', () {
      expect(isWorkspaceV1(<String, dynamic>{'schemaVersion': 1}), isFalse);
    });

    test('round-trips a workspace snapshot through JSON', () {
      final workspace = PersistedWorkspace(
        savedAt: 42,
        preferences: WorkspacePreferences(
          theme: 'dark',
          bgImageUrl: defaultWallpaper,
          bgBlur: 12,
          sidebarCollapsed: false,
        ),
        desktop: WorkspaceDesktop(
          activeNavIndex: 1,
          activeWindowId: 'w1',
          windows: [
            PersistedWindow(
              id: 'w1',
              toolId: 'json',
              geometry:
                  const WindowGeometry(x: 10, y: 20, width: 900, height: 650),
              zIndex: 11,
              isMinimized: false,
              isMaximized: false,
            ),
          ],
        ),
        todos: [TodoItem(id: 't1', text: '写周报', done: false)],
        timers: defaultTimerSnapshot(),
        workspaceTemplates: [],
        launcher: defaultLauncherPreferences(),
      );
      final json = workspace.toJson();
      expect(isWorkspaceV1(json), isTrue);
      final restored = PersistedWorkspace.fromJson(json);
      expect(restored.desktop.windows.single.toolId, 'json');
      expect(restored.todos.single.text, '写周报');
      expect(restored.preferences.theme, 'dark');
    });

    test('migrates legacy floating-window aliases', () {
      expect(migrateWindowToolId('json-format'), 'json');
      expect(migrateWindowToolId('hash-check'), 'hash');
      expect(migrateWindowToolId('timestamp'), 'timer');
    });

    test('contains unique tool IDs and a builder for every window tool', () {
      final ids = toolRegistry.map((tool) => tool.id).toList();
      expect(ids.toSet().length, ids.length);
      final builderKeys = windowToolBuilders.keys.toList()..sort();
      final windowIds = windowTools.map((tool) => tool.id).toList()..sort();
      expect(builderKeys, windowIds);
    });
  });
}
