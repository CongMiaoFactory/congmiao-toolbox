import 'dart:io';

import 'package:congmiao_toolbox_flutter/core/peek_server.dart'
    show ForegroundWindowInfo;
import 'package:congmiao_toolbox_flutter/core/usage_tracker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('congmiao_usage'));
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // Best-effort cleanup.
    }
  });

  test('accumulates seconds per app and persists like the Rust tracker', () {
    final file = File(p.join(dir.path, 'app_usage.json'));
    final windows = [
      const ForegroundWindowInfo(title: 'Code', processName: 'Code'),
      const ForegroundWindowInfo(title: 'Code', processName: 'Code'),
      const ForegroundWindowInfo(title: '浏览器', processName: 'msedge'),
      null,
    ];
    var call = 0;
    final tracker = UsageTracker(
      saveFile: file,
      windowProvider: () => windows[call++ % windows.length],
    );

    for (var tick = 0; tick < 12; tick++) {
      tracker.tick();
    }

    final usage = tracker.appUsage();
    expect(usage.first.appName, 'Code');
    expect(usage.first.seconds, 6);
    expect(usage[1].appName, 'msedge');
    expect(usage[1].seconds, 3);
    expect(tracker.lastWindow?.processName, isNotNull);
    // The tenth tick triggered a save; reload into a fresh tracker.
    expect(file.existsSync(), isTrue);
    final reloaded = UsageTracker(saveFile: file, windowProvider: () => null)
      ..loadFromDisk();
    expect(reloaded.totals['Code'], greaterThanOrEqualTo(5));
  });
}
