import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;

import 'file_tools.dart' show appDataDirectory;
import 'peek_security.dart';
import 'peek_server.dart';
import 'system_stats.dart';
import 'usage_tracker.dart';

/// App-level singletons wiring the pure-Dart services (Peek security +
/// server, system stats, usage tracker) to the Flutter app: storage paths in
/// the shared app-data directory and mobile dashboard assets from the bundle.
class AppServices {
  AppServices._();

  static final AppServices instance = AppServices._();

  late final PeekSecurityState peekSecurity = PeekSecurityState.load(
      File(p.join(appDataDirectory(), 'peek-security.json')));

  final SystemStatsService systemStats = SystemStatsService();

  late final UsageTracker usageTracker = UsageTracker(
      saveFile: File(p.join(appDataDirectory(), 'app_usage.json')));

  PeekServer? _peekServer;

  Future<PeekServer> peekServer() async {
    final existing = _peekServer;
    if (existing != null) return existing;
    final assets = PeekMobileAssets(
      html: await rootBundle.loadString('assets/peek/peek-mobile.html'),
      css: await rootBundle.loadString('assets/peek/peek-mobile.css'),
      js: await rootBundle.loadString('assets/peek/peek-mobile.js'),
    );
    return _peekServer = PeekServer(
      security: peekSecurity,
      stats: systemStats,
      assets: assets,
      foregroundWindow: () => usageTracker.lastWindow ?? readForegroundWindow(),
    );
  }
}
