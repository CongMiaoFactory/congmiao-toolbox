import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'peek_security.dart';
import 'system_stats.dart';

/// Dart port of the Peek PC LAN server (`peek_server/mod.rs`), built on
/// `dart:io` HttpServer: Bearer-token auth middleware backed by
/// [PeekSecurityState], hardened response headers, the mobile dashboard and
/// the /api/status + /api/privacy endpoints. Screenshots need native screen
/// capture and answer 501 until a platform channel lands.
class ForegroundWindowInfo {
  const ForegroundWindowInfo({required this.title, required this.processName});

  final String title;
  final String processName;

  Map<String, dynamic> toJson() =>
      {'title': title, 'processName': processName};
}

class PeekMobileAssets {
  const PeekMobileAssets({
    required this.html,
    required this.css,
    required this.js,
  });

  final String html;
  final String css;
  final String js;
}

class PeekServer {
  PeekServer({
    required this.security,
    required this.stats,
    required this.assets,
    this.foregroundWindow,
  });

  final PeekSecurityState security;
  final SystemStatsService stats;
  final PeekMobileAssets assets;
  final ForegroundWindowInfo? Function()? foregroundWindow;

  HttpServer? _server;
  bool privacyMode = false;

  bool get isRunning => _server != null;

  int get boundPort => _server?.port ?? security.config.port;

  Future<String> serverUrl() async {
    final config = security.config;
    if (config.listenScope == 'local' || _server == null) {
      return 'http://127.0.0.1:$boundPort';
    }
    try {
      final interfaces = await NetworkInterface.list(
          includeLoopback: false, type: InternetAddressType.IPv4);
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (!address.isLoopback) return 'http://${address.address}:$boundPort';
        }
      }
    } on SocketException {
      // Fall through to loopback below.
    }
    return 'http://127.0.0.1:$boundPort';
  }

  Future<void> start({int? portOverride}) async {
    if (_server != null) {
      throw const PeekSecurityException('Peek PC 服务已经在运行');
    }
    if (!security.hasApiKey) {
      throw const PeekSecurityException('请先生成 Peek PC API 密钥');
    }
    final config = security.config;
    final address = config.listenScope == 'local'
        ? InternetAddress.loopbackIPv4
        : InternetAddress.anyIPv4;
    final HttpServer server;
    try {
      server = await HttpServer.bind(address, portOverride ?? config.port);
    } on SocketException catch (error) {
      security.logServerEvent('server_start_failed', false);
      throw PeekSecurityException('端口监听失败：${error.message}');
    }
    _server = server;
    security.logServerEvent('server_started', true);
    unawaited(_serve(server));
  }

  Future<void> stop() async {
    final server = _server;
    if (server == null) return;
    _server = null;
    await server.close(force: true);
    security.logServerEvent('server_stopped', true);
  }

  Future<void> _serve(HttpServer server) async {
    await for (final request in server) {
      unawaited(_handle(request).catchError((Object _) async {
        try {
          await request.response.close();
        } catch (_) {
          // Client already disconnected.
        }
      }));
    }
  }

  void _securityHeaders(HttpResponse response) {
    response.headers
      ..set('x-content-type-options', 'nosniff')
      ..set('x-frame-options', 'DENY')
      ..set('referrer-policy', 'no-referrer')
      ..set('cache-control', 'no-store');
  }

  Future<void> _json(HttpRequest request, int status, Object body) async {
    final response = request.response;
    response.statusCode = status;
    _securityHeaders(response);
    response.headers.contentType =
        ContentType('application', 'json', charset: 'utf-8');
    response.write(jsonEncode(body));
    await response.close();
  }

  Future<void> _text(
      HttpRequest request, String contentType, String body) async {
    final response = request.response;
    _securityHeaders(response);
    final parts = contentType.split('/');
    response.headers.contentType =
        ContentType(parts.first, parts.last, charset: 'utf-8');
    if (contentType == 'text/html') {
      response.headers.set('content-security-policy',
          "default-src 'self'; img-src 'self' blob: data:; connect-src 'self'; style-src 'self'; script-src 'self'; object-src 'none'; frame-ancestors 'none'");
    }
    response.write(body);
    await response.close();
  }

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    final method = request.method;

    if (method == 'GET' && path == '/') {
      return _text(request, 'text/html', assets.html);
    }
    if (method == 'GET' && path == '/peek-mobile.css') {
      return _text(request, 'text/css', assets.css);
    }
    if (method == 'GET' && path == '/peek-mobile.js') {
      return _text(request, 'text/javascript', assets.js);
    }

    if (path.startsWith('/api/')) {
      final authorization = request.headers.value('authorization') ?? '';
      final token = authorization.startsWith('Bearer ')
          ? authorization.substring(7)
          : '';
      final ip = request.connectionInfo?.remoteAddress.address ?? 'unknown';
      final endpoint = path.substring('/api/'.length);
      switch (security.authenticate(token, ip, endpoint)) {
        case AuthOutcome.denied:
          return _json(request, HttpStatus.unauthorized,
              {'code': 'unauthorized', 'message': 'API 密钥无效'});
        case AuthOutcome.rateLimited:
          return _json(request, HttpStatus.tooManyRequests,
              {'code': 'rate_limited', 'message': '认证失败次数过多，请稍后再试'});
        case AuthOutcome.granted:
          break;
      }

      if (method == 'GET' && path == '/api/status') {
        final sampled = await stats.sample();
        return _json(request, HttpStatus.ok, {
          'status': 'ok',
          'cpu': sampled.cpu,
          'memory': sampled.toStatusJson(),
          'foregroundWindow': foregroundWindow?.call()?.toJson(),
          'media': null,
        });
      }
      if (method == 'GET' && path == '/api/screenshot') {
        return _json(request, HttpStatus.notImplemented, {
          'code': 'not_supported',
          'message': '截图功能待 Flutter 版接入原生屏幕捕获',
        });
      }
      if (path == '/api/privacy') {
        if (method == 'POST') privacyMode = !privacyMode;
        if (method == 'GET' || method == 'POST') {
          return _json(request, HttpStatus.ok, {
            'enabled': privacyMode,
            'message': privacyMode ? '隐私模式已开启' : '隐私模式已关闭',
          });
        }
      }
      return _json(request, HttpStatus.notFound,
          {'code': 'not_found', 'message': '接口不存在'});
    }

    return _json(request, HttpStatus.notFound,
        {'code': 'not_found', 'message': '页面不存在'});
  }
}
