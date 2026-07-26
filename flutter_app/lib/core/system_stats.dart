import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Cross-platform CPU / memory sampling without platform channels — the
/// Flutter counterpart of the Rust `sysinfo` usage. Windows shells out to
/// PowerShell CIM, Linux reads /proc, macOS parses `top`. Values are cached
/// so UI tiles and the Peek server share one sampler.
class SystemStats {
  const SystemStats({
    required this.cpu,
    required this.totalMb,
    required this.usedMb,
    required this.availableMb,
  });

  static const empty =
      SystemStats(cpu: 0, totalMb: 0, usedMb: 0, availableMb: 0);

  final double cpu;
  final double totalMb;
  final double usedMb;
  final double availableMb;

  double get usedPercent => totalMb <= 0 ? 0 : (usedMb / totalMb) * 100;

  Map<String, dynamic> toStatusJson() => {
        'total': totalMb,
        'used': usedMb,
        'available': availableMb,
        'usedPercent': usedPercent,
      };
}

class SystemStatsService {
  SystemStatsService({this.cacheDuration = const Duration(seconds: 2)});

  final Duration cacheDuration;
  SystemStats latest = SystemStats.empty;
  DateTime _sampledAt = DateTime.fromMillisecondsSinceEpoch(0);
  Future<SystemStats>? _inFlight;

  // Previous /proc/stat totals for Linux CPU deltas.
  int _lastIdle = 0;
  int _lastTotal = 0;

  Future<SystemStats> sample() {
    if (DateTime.now().difference(_sampledAt) < cacheDuration) {
      return Future.value(latest);
    }
    return _inFlight ??= _sampleNow().then((stats) {
      latest = stats;
      _sampledAt = DateTime.now();
      return stats;
    }).whenComplete(() => _inFlight = null);
  }

  Future<SystemStats> _sampleNow() async {
    try {
      if (Platform.isWindows) return await _sampleWindows();
      if (Platform.isLinux) return await _sampleLinux();
      if (Platform.isMacOS) return await _sampleMacOS();
    } catch (_) {
      // Fall through to the last known value below.
    }
    return latest;
  }

  Future<SystemStats> _sampleWindows() async {
    const script =
        r'$os=Get-CimInstance Win32_OperatingSystem;$cpu=(Get-CimInstance Win32_Processor|Measure-Object -Property LoadPercentage -Average).Average;[Console]::Out.Write((ConvertTo-Json @{cpu=$cpu;totalKb=$os.TotalVisibleMemorySize;freeKb=$os.FreePhysicalMemory} -Compress))';
    final result = await Process.run(
      'powershell',
      ['-NoProfile', '-NonInteractive', '-Command', script],
      stdoutEncoding: utf8,
    );
    if (result.exitCode != 0) return latest;
    final decoded = jsonDecode(result.stdout as String);
    if (decoded is! Map<String, dynamic>) return latest;
    final totalKb = (decoded['totalKb'] as num?)?.toDouble() ?? 0;
    final freeKb = (decoded['freeKb'] as num?)?.toDouble() ?? 0;
    return SystemStats(
      cpu: (decoded['cpu'] as num?)?.toDouble() ?? 0,
      totalMb: totalKb / 1024,
      usedMb: (totalKb - freeKb) / 1024,
      availableMb: freeKb / 1024,
    );
  }

  Future<SystemStats> _sampleLinux() async {
    final memLines = await File('/proc/meminfo').readAsLines();
    double readKb(String prefix) {
      for (final line in memLines) {
        if (line.startsWith(prefix)) {
          final match = RegExp(r'(\d+)').firstMatch(line);
          if (match != null) return double.parse(match.group(1)!);
        }
      }
      return 0;
    }

    final totalKb = readKb('MemTotal:');
    final availableKb = readKb('MemAvailable:');

    final statLine = (await File('/proc/stat').readAsLines()).first;
    final parts = statLine
        .split(RegExp(r'\s+'))
        .skip(1)
        .map((value) => int.tryParse(value) ?? 0)
        .toList();
    final idle = parts.length > 4 ? parts[3] + parts[4] : 0;
    final total = parts.fold<int>(0, (sum, value) => sum + value);
    var cpu = latest.cpu;
    if (_lastTotal > 0 && total > _lastTotal) {
      final idleDelta = idle - _lastIdle;
      final totalDelta = total - _lastTotal;
      cpu = (1 - idleDelta / totalDelta) * 100;
    }
    _lastIdle = idle;
    _lastTotal = total;

    return SystemStats(
      cpu: cpu.clamp(0, 100).toDouble(),
      totalMb: totalKb / 1024,
      usedMb: (totalKb - availableKb) / 1024,
      availableMb: availableKb / 1024,
    );
  }

  Future<SystemStats> _sampleMacOS() async {
    final result = await Process.run('top', ['-l', '1', '-n', '0']);
    if (result.exitCode != 0) return latest;
    final output = result.stdout as String;
    final cpuMatch = RegExp(r'CPU usage:\s*([\d.]+)% user,\s*([\d.]+)% sys')
        .firstMatch(output);
    final cpu = cpuMatch == null
        ? latest.cpu
        : double.parse(cpuMatch.group(1)!) + double.parse(cpuMatch.group(2)!);
    final memMatch = RegExp(r'PhysMem:\s*(\d+)([MG]) used.*?(\d+)([MG]) unused')
        .firstMatch(output);
    double toMb(String value, String unit) =>
        double.parse(value) * (unit == 'G' ? 1024 : 1);
    if (memMatch == null) {
      return SystemStats(
        cpu: cpu.clamp(0, 100).toDouble(),
        totalMb: latest.totalMb,
        usedMb: latest.usedMb,
        availableMb: latest.availableMb,
      );
    }
    final used = toMb(memMatch.group(1)!, memMatch.group(2)!);
    final unused = toMb(memMatch.group(3)!, memMatch.group(4)!);
    return SystemStats(
      cpu: cpu.clamp(0, 100).toDouble(),
      totalMb: used + unused,
      usedMb: used,
      availableMb: unused,
    );
  }
}
