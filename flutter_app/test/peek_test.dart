import 'dart:convert';
import 'dart:io';

import 'package:congmiao_toolbox_flutter/core/peek_security.dart';
import 'package:congmiao_toolbox_flutter/core/peek_server.dart';
import 'package:congmiao_toolbox_flutter/core/system_stats.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _FakeStats extends SystemStatsService {
  @override
  Future<SystemStats> sample() async => const SystemStats(
      cpu: 12.5, totalMb: 16000, usedMb: 8000, availableMb: 8000);
}

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('congmiao_peek'));
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // Best-effort cleanup.
    }
  });

  File securityFile() => File(p.join(dir.path, 'peek-security.json'));

  group('peek security (port of security.rs tests)', () {
    test('generated key authenticates and raw key is not persisted', () {
      final state = PeekSecurityState.load(securityFile());
      final issued = state.generateApiKey();
      expect(issued.apiKey.length, 64);
      expect(state.authenticate(issued.apiKey, '127.0.0.1', 'status'),
          AuthOutcome.granted);
      expect(securityFile().readAsStringSync().contains(issued.apiKey),
          isFalse);
    });

    test('regenerating the key invalidates the previous key', () {
      final state = PeekSecurityState.load(securityFile());
      final first = state.generateApiKey();
      final second = state.generateApiKey();
      expect(state.authenticate(first.apiKey, '127.0.0.1', 'status'),
          AuthOutcome.denied);
      expect(state.authenticate(second.apiKey, '127.0.0.1', 'status'),
          AuthOutcome.granted);
    });

    test('repeated auth failures are rate limited', () {
      final state = PeekSecurityState.load(securityFile());
      state.generateApiKey();
      for (var attempt = 0; attempt < maxAuthFailures; attempt++) {
        state.authenticate('bad', '10.0.0.2', 'status');
      }
      expect(state.authenticate('bad', '10.0.0.2', 'status'),
          AuthOutcome.rateLimited);
    });

    test('server config is validated', () {
      final state = PeekSecurityState.load(securityFile());
      expect(
          () => state
              .setConfig(PeekServerConfig(listenScope: 'public', port: 3000)),
          throwsA(isA<PeekSecurityException>()));
      expect(
          () => state
              .setConfig(PeekServerConfig(listenScope: 'local', port: 1023)),
          throwsA(isA<PeekSecurityException>()));
    });

    test('legacy v1 migration discards device tokens', () {
      securityFile().writeAsStringSync(
          '{"schemaVersion":1,"config":{"listenScope":"lan","port":3456},'
          '"devices":[{"tokenHash":"secret"}],"logs":[]}');
      final state = PeekSecurityState.load(securityFile());
      expect(state.hasApiKey, isFalse);
      expect(state.config.port, 3456);
    });

    test('state survives reload from disk', () {
      final first = PeekSecurityState.load(securityFile());
      final issued = first.generateApiKey();
      first.setConfig(PeekServerConfig(listenScope: 'local', port: 4567));

      final second = PeekSecurityState.load(securityFile());
      expect(second.hasApiKey, isTrue);
      expect(second.config.listenScope, 'local');
      expect(second.config.port, 4567);
      expect(second.authenticate(issued.apiKey, '127.0.0.1', 'status'),
          AuthOutcome.granted);
    });
  });

  group('peek server (dart:io HttpServer)', () {
    test('serves the dashboard and enforces auth end to end', () async {
      final security = PeekSecurityState.load(securityFile());
      final issued = security.generateApiKey();
      final server = PeekServer(
        security: security,
        stats: _FakeStats(),
        assets: const PeekMobileAssets(
            html: '<main>PEEK-TEST</main>', css: 'body{}', js: '// js'),
        foregroundWindow: () =>
            const ForegroundWindowInfo(title: '窗口', processName: 'test.exe'),
      );
      await server.start(portOverride: 0);
      final base = 'http://127.0.0.1:${server.boundPort}';
      final client = HttpClient();

      Future<(int, String)> call(String path,
          {String? token, String method = 'GET'}) async {
        final request = await client.openUrl(method, Uri.parse('$base$path'));
        if (token != null) {
          request.headers.set('authorization', 'Bearer $token');
        }
        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();
        return (response.statusCode, body);
      }

      try {
        final (homeStatus, homeBody) = await call('/');
        expect(homeStatus, 200);
        expect(homeBody, contains('PEEK-TEST'));

        final (unauthorized, _) = await call('/api/status');
        expect(unauthorized, 401);

        final (ok, statusBody) =
            await call('/api/status', token: issued.apiKey);
        expect(ok, 200);
        final status = jsonDecode(statusBody) as Map<String, dynamic>;
        expect(status['cpu'], 12.5);
        expect((status['memory'] as Map)['usedPercent'], 50.0);
        expect((status['foregroundWindow'] as Map)['processName'], 'test.exe');

        final (screenshot, _) =
            await call('/api/screenshot', token: issued.apiKey);
        expect(screenshot, 501);

        final (_, privacyBody) = await call('/api/privacy',
            token: issued.apiKey, method: 'POST');
        expect((jsonDecode(privacyBody) as Map)['enabled'], isTrue);
      } finally {
        client.close(force: true);
        await server.stop();
      }
    });

    test('refuses to start without an API key', () async {
      final security = PeekSecurityState.load(securityFile());
      final server = PeekServer(
        security: security,
        stats: _FakeStats(),
        assets: const PeekMobileAssets(html: '', css: '', js: ''),
      );
      await expectLater(server.start(portOverride: 0),
          throwsA(isA<PeekSecurityException>()));
    });
  });
}
