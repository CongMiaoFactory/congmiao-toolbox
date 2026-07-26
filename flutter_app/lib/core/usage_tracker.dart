import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart';

import 'peek_server.dart' show ForegroundWindowInfo;

/// Dart port of `usage_tracker.rs`: sample the foreground application once a
/// second, accumulate per-app seconds and persist every ten ticks to
/// `app_usage.json` (same file name and shape as the Rust build). The
/// foreground probe uses win32 FFI, so tracking is Windows-only for now;
/// other platforms simply report an empty list.
class AppUsage {
  const AppUsage({required this.appName, required this.seconds});

  final String appName;
  final int seconds;
}

const _processQueryLimitedInformation = 0x1000;

ForegroundWindowInfo? readForegroundWindow() {
  if (!Platform.isWindows) return null;
  final hwnd = GetForegroundWindow();
  if (hwnd == 0) return null;

  final titleBuffer = calloc<Uint16>(512).cast<Utf16>();
  final pidBuffer = calloc<Uint32>();
  final pathBuffer = calloc<Uint16>(MAX_PATH).cast<Utf16>();
  final sizeBuffer = calloc<Uint32>()..value = MAX_PATH;
  try {
    final titleLength = GetWindowText(hwnd, titleBuffer, 512);
    final title = titleLength > 0 ? titleBuffer.toDartString() : '';

    GetWindowThreadProcessId(hwnd, pidBuffer);
    final pid = pidBuffer.value;
    if (pid == 0) return null;

    var processName = '';
    final handle =
        OpenProcess(_processQueryLimitedInformation, FALSE, pid);
    if (handle != 0) {
      try {
        if (QueryFullProcessImageName(handle, 0, pathBuffer, sizeBuffer) !=
            0) {
          processName = p.basenameWithoutExtension(pathBuffer.toDartString());
        }
      } finally {
        CloseHandle(handle);
      }
    }
    if (processName.isEmpty && title.isEmpty) return null;
    return ForegroundWindowInfo(
      title: title,
      processName: processName.isEmpty ? title : processName,
    );
  } finally {
    free(titleBuffer);
    free(pidBuffer);
    free(pathBuffer);
    free(sizeBuffer);
  }
}

class UsageTracker {
  UsageTracker({
    required this.saveFile,
    ForegroundWindowInfo? Function()? windowProvider,
  }) : _windowProvider = windowProvider ?? readForegroundWindow;

  final File saveFile;
  final ForegroundWindowInfo? Function() _windowProvider;
  final Map<String, int> totals = {};

  ForegroundWindowInfo? lastWindow;
  Timer? _timer;
  int _saveTick = 0;

  bool get supported => Platform.isWindows;

  bool get running => _timer != null;

  void loadFromDisk() {
    if (!saveFile.existsSync()) return;
    try {
      final decoded = jsonDecode(saveFile.readAsStringSync());
      if (decoded is Map<String, dynamic>) {
        totals
          ..clear()
          ..addAll({
            for (final entry in decoded.entries)
              if (entry.value is num) entry.key: (entry.value as num).toInt(),
          });
      }
    } on FormatException {
      // A corrupt usage file simply restarts the counters.
    }
  }

  void start() {
    if (_timer != null || !supported) return;
    loadFromDisk();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    saveToDisk();
  }

  /// One sampling step; extracted so tests can drive it directly.
  void tick() {
    final window = _windowProvider();
    if (window != null) {
      lastWindow = window;
      final name = window.processName.trim();
      if (name.isNotEmpty) {
        totals.update(name, (seconds) => seconds + 1, ifAbsent: () => 1);
      }
    }
    _saveTick += 1;
    if (_saveTick >= 10) {
      _saveTick = 0;
      saveToDisk();
    }
  }

  void saveToDisk() {
    try {
      saveFile.parent.createSync(recursive: true);
      saveFile.writeAsStringSync(jsonEncode(totals));
    } on FileSystemException {
      // Persisting usage is best-effort, matching the Rust tracker.
    }
  }

  List<AppUsage> appUsage() {
    final entries = [
      for (final entry in totals.entries)
        AppUsage(appName: entry.key, seconds: entry.value),
    ]..sort((a, b) => b.seconds.compareTo(a.seconds));
    return entries;
  }

  void reset() {
    totals.clear();
    saveToDisk();
  }
}
