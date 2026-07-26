import 'package:congmiao_toolbox_flutter/core/launcher.dart';
import 'package:congmiao_toolbox_flutter/core/tool_registry.dart';
import 'package:flutter_test/flutter_test.dart';

/// Dart port of `src/launcher.test.ts`.
void main() {
  group('quick launcher', () {
    test('scores fuzzy matches and boosts favorites', () {
      expect(fuzzyScore('json', 'json 格式化'), greaterThan(0));
      final results =
          buildLauncherResults('', toolRegistry, [], ['timer'], []);
      expect(results.first.toolId, 'timer');
    });

    test('parses safe calculations without eval', () {
      expect(calculate('=(2 + 3) * 4'), 20);
      expect(calculate('2 ** 8'), isNull);
      expect(calculate('alert(1)'), isNull);
    });

    test('creates timer, todo and URL actions', () {
      final timer =
          buildLauncherResults('> timer 10m', toolRegistry, [], [], []).first;
      expect(timer.kind, LauncherResultKind.timer);
      expect(timer.seconds, 600);

      final todo =
          buildLauncherResults('> todo 提交项目', toolRegistry, [], [], []).first;
      expect(todo.kind, LauncherResultKind.todo);
      expect(todo.value, '提交项目');

      final url =
          buildLauncherResults('example.com', toolRegistry, [], [], []).first;
      expect(url.kind, LauncherResultKind.url);
    });

    test('normalizes URLs like the original', () {
      expect(normalizeUrl('example.com'), 'https://example.com');
      expect(normalizeUrl('https://example.com/path?q=1'),
          'https://example.com/path?q=1');
      expect(normalizeUrl('ftp://example.com'), isNull);
      expect(normalizeUrl('not a url'), isNull);
    });

    test('parses timer commands with units', () {
      expect(parseTimerCommand('> timer 90s'), 90);
      expect(parseTimerCommand('> timer 1.5h'), 5400);
      expect(parseTimerCommand('> timer 0s'), isNull);
      expect(parseTimerCommand('> timer 100000'), isNull);
    });
  });
}
