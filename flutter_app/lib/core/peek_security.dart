import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'ids.dart';

/// Dart port of `src-tauri/src/peek_server/security.rs`: persisted server
/// config, a single hashed high-entropy API key, failed-auth throttling and
/// debounced connection logs. The on-disk schema (v2, camelCase) matches the
/// Rust build; only the hash algorithm differs (SHA-256 instead of BLAKE3),
/// so migrated installs simply regenerate their key.
const securitySchemaVersion = 2;
const attemptWindowMs = 60 * 1000;
const maxAuthFailures = 10;
const maxLogs = 500;
const logRetentionMs = 30 * 24 * 60 * 60 * 1000;
const accessLogDebounceMs = 30 * 1000;

class PeekServerConfig {
  PeekServerConfig({required this.listenScope, required this.port});

  factory PeekServerConfig.defaults() =>
      PeekServerConfig(listenScope: 'lan', port: 3000);

  factory PeekServerConfig.fromJson(Map<String, dynamic> json) =>
      PeekServerConfig(
        listenScope: json['listenScope'] == 'local' ? 'local' : 'lan',
        port: (json['port'] as num?)?.toInt() ?? 3000,
      );

  String listenScope; // lan | local
  int port;

  Map<String, dynamic> toJson() => {'listenScope': listenScope, 'port': port};
}

class ConnectionLog {
  ConnectionLog({
    required this.id,
    required this.timestamp,
    required this.ip,
    required this.event,
    required this.success,
  });

  factory ConnectionLog.fromJson(Map<String, dynamic> json) => ConnectionLog(
        id: json['id'] as String? ?? '',
        timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
        ip: json['ip'] as String? ?? '',
        event: json['event'] as String? ?? '',
        success: json['success'] as bool? ?? false,
      );

  final String id;
  final int timestamp;
  final String ip;
  final String event;
  final bool success;

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp,
        'ip': ip,
        'event': event,
        'success': success,
      };
}

class PeekSecuritySnapshot {
  const PeekSecuritySnapshot({
    required this.config,
    required this.apiKeyConfigured,
    required this.apiKeyCreatedAt,
    required this.logs,
  });

  final PeekServerConfig config;
  final bool apiKeyConfigured;
  final int? apiKeyCreatedAt;
  final List<ConnectionLog> logs;
}

class IssuedApiKey {
  const IssuedApiKey({required this.apiKey, required this.createdAt});

  final String apiKey;
  final int createdAt;
}

enum AuthOutcome { granted, denied, rateLimited }

class PeekSecurityException implements Exception {
  const PeekSecurityException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _PersistedSecurity {
  _PersistedSecurity({
    required this.config,
    this.apiKeyHash,
    this.apiKeyCreatedAt,
    required this.logs,
  });

  PeekServerConfig config;
  String? apiKeyHash;
  int? apiKeyCreatedAt;
  List<ConnectionLog> logs;

  Map<String, dynamic> toJson() => {
        'schemaVersion': securitySchemaVersion,
        'config': config.toJson(),
        'apiKeyHash': apiKeyHash,
        'apiKeyCreatedAt': apiKeyCreatedAt,
        'logs': logs.map((log) => log.toJson()).toList(),
      };
}

int _nowMs() => DateTime.now().millisecondsSinceEpoch;

String tokenHash(String token) =>
    sha256.convert(utf8.encode(token)).toString();

/// Constant-time string comparison so auth timing does not leak prefixes.
bool constantTimeEquals(String a, String b) {
  final aUnits = a.codeUnits;
  final bUnits = b.codeUnits;
  var diff = aUnits.length ^ bUnits.length;
  final length = aUnits.length < bUnits.length ? aUnits.length : bUnits.length;
  for (var index = 0; index < length; index++) {
    diff |= aUnits[index] ^ bUnits[index];
  }
  return diff == 0;
}

class PeekSecurityState {
  PeekSecurityState._(this._file, this._data);

  /// Loads (or migrates) the persisted state. Mirrors `load`: restores from
  /// the .bak file, quarantines corrupt documents and migrates schema v1 by
  /// discarding the per-device tokens.
  factory PeekSecurityState.load(File file) {
    final backup = File('${file.path}.bak');
    if (!file.existsSync() && backup.existsSync()) {
      backup.renameSync(file.path);
    }
    _PersistedSecurity? persisted;
    if (file.existsSync()) {
      persisted = _read(file);
      if (persisted == null) {
        final corrupt = File(
            '${file.parent.path}${Platform.pathSeparator}peek-security.corrupt.${_nowMs()}.json');
        try {
          file.copySync(corrupt.path);
          file.deleteSync();
        } on FileSystemException {
          // Quarantine is best-effort.
        }
      }
    }
    return PeekSecurityState._(
      file,
      persisted ??
          _PersistedSecurity(
              config: PeekServerConfig.defaults(), logs: <ConnectionLog>[]),
    );
  }

  final File _file;
  final _PersistedSecurity _data;
  final Map<String, List<int>> _failedAttempts = {};
  final Map<String, int> _lastLogWrite = {};

  static _PersistedSecurity? _read(File file) {
    final Object? decoded;
    try {
      decoded = jsonDecode(file.readAsStringSync());
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    final schema = (decoded['schemaVersion'] as num?)?.toInt();
    final config = decoded['config'];
    if (config is! Map<String, dynamic>) return null;
    final logs = decoded['logs'] is List
        ? (decoded['logs'] as List)
            .whereType<Map<String, dynamic>>()
            .map(ConnectionLog.fromJson)
            .toList()
        : <ConnectionLog>[];
    final now = _nowMs();
    logs.retainWhere((log) => now - log.timestamp <= logRetentionMs);
    if (logs.length > maxLogs) logs.removeRange(maxLogs, logs.length);

    if (schema == securitySchemaVersion) {
      return _PersistedSecurity(
        config: PeekServerConfig.fromJson(config),
        apiKeyHash: decoded['apiKeyHash'] as String?,
        apiKeyCreatedAt: (decoded['apiKeyCreatedAt'] as num?)?.toInt(),
        logs: logs,
      );
    }
    if (schema == 1) {
      // v0.2.7 stored one token per paired device; those are deliberately
      // invalidated during migration.
      return _PersistedSecurity(
          config: PeekServerConfig.fromJson(config), logs: logs);
    }
    return null;
  }

  void _save() {
    _file.parent.createSync(recursive: true);
    final path = _file.path;
    final temp = File('$path.tmp');
    final backup = File('$path.bak');
    temp.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(_data.toJson()));
    if (backup.existsSync()) backup.deleteSync();
    if (_file.existsSync()) _file.renameSync(backup.path);
    try {
      temp.renameSync(path);
    } on FileSystemException catch (error) {
      if (backup.existsSync()) {
        try {
          backup.renameSync(path);
        } on FileSystemException {
          // Leave the backup for manual recovery.
        }
      }
      throw PeekSecurityException(error.message);
    }
    if (backup.existsSync()) {
      try {
        backup.deleteSync();
      } on FileSystemException {
        // Stale backup is harmless.
      }
    }
  }

  void _pushLog(String ip, String event, bool success) {
    final now = _nowMs();
    _data.logs.insert(
      0,
      ConnectionLog(
          id: generateId(),
          timestamp: now,
          ip: ip,
          event: event,
          success: success),
    );
    _data.logs.retainWhere((log) => now - log.timestamp <= logRetentionMs);
    if (_data.logs.length > maxLogs) {
      _data.logs.removeRange(maxLogs, _data.logs.length);
    }
  }

  PeekSecuritySnapshot snapshot() => PeekSecuritySnapshot(
        config: PeekServerConfig(
            listenScope: _data.config.listenScope, port: _data.config.port),
        apiKeyConfigured: _data.apiKeyHash != null,
        apiKeyCreatedAt: _data.apiKeyCreatedAt,
        logs: List.of(_data.logs),
      );

  PeekServerConfig get config => PeekServerConfig(
      listenScope: _data.config.listenScope, port: _data.config.port);

  bool get hasApiKey => _data.apiKeyHash != null;

  PeekServerConfig setConfig(PeekServerConfig config) {
    if (config.listenScope != 'lan' && config.listenScope != 'local') {
      throw const PeekSecurityException('监听范围必须是 lan 或 local');
    }
    if (config.port < 1024 || config.port > 65535) {
      throw const PeekSecurityException('端口必须在 1024 到 65535 之间');
    }
    _data.config = config;
    _save();
    return config;
  }

  IssuedApiKey generateApiKey() {
    final apiKey = generateId().replaceAll('-', '') +
        generateId().replaceAll('-', '');
    final createdAt = _nowMs();
    _data.apiKeyHash = tokenHash(apiKey);
    _data.apiKeyCreatedAt = createdAt;
    _pushLog('local', 'api_key_regenerated', true);
    _save();
    _failedAttempts.clear();
    return IssuedApiKey(apiKey: apiKey, createdAt: createdAt);
  }

  bool _isRateLimited(String ip, {required bool recordFailure}) {
    final now = _nowMs();
    final values = _failedAttempts.putIfAbsent(ip, () => []);
    values.retainWhere((time) => now - time < attemptWindowMs);
    if (values.length >= maxAuthFailures) return true;
    if (recordFailure) values.add(now);
    return false;
  }

  AuthOutcome authenticate(String token, String ip, String endpoint) {
    if (_isRateLimited(ip, recordFailure: false)) {
      _logDebounced(ip, 'auth_rate_limited', false);
      return AuthOutcome.rateLimited;
    }
    final stored = _data.apiKeyHash;
    final valid = token.length == 64 &&
        stored != null &&
        constantTimeEquals(stored, tokenHash(token));
    if (!valid) {
      final limited = _isRateLimited(ip, recordFailure: true);
      _logDebounced(ip, 'unauthorized', false);
      return limited ? AuthOutcome.rateLimited : AuthOutcome.denied;
    }
    _failedAttempts.remove(ip);
    _logDebounced(ip, endpoint, true);
    return AuthOutcome.granted;
  }

  List<ConnectionLog> get logs => snapshot().logs;

  void clearLogs() {
    _data.logs.clear();
    _save();
  }

  void logServerEvent(String event, bool success) {
    _pushLog('local', event, success);
    _save();
  }

  void _logDebounced(String ip, String event, bool success) {
    final now = _nowMs();
    final group = success ? 'access' : event;
    final key = '$ip:$group:$success';
    final last = _lastLogWrite[key] ?? 0;
    if (now - last < accessLogDebounceMs) return;
    _lastLogWrite[key] = now;
    _pushLog(ip, event, success);
    _save();
  }
}
