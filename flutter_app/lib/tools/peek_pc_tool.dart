import 'package:flutter/material.dart';

import '../core/app_services.dart';
import '../core/app_state.dart';
import '../core/peek_security.dart';
import '../core/peek_server.dart';
import '../core/tool_registry.dart';
import 'actions.dart';

/// Peek PC control window (PeekPCTool.svelte): start/stop the LAN server,
/// manage the single high-entropy API key, tune the listener and inspect
/// connection logs. The phone opens the served dashboard in its browser.
class PeekPCTool extends StatefulWidget {
  const PeekPCTool({super.key, required this.appState});

  final AppState appState;

  @override
  State<PeekPCTool> createState() => _PeekPCToolState();
}

class _PeekPCToolState extends State<PeekPCTool> {
  final TextEditingController _portController = TextEditingController();
  PeekServer? _server;
  String? _serverUrl;
  String? _message;
  bool _messageIsError = false;
  bool _busy = false;

  PeekSecurityState get security => AppServices.instance.peekSecurity;

  @override
  void initState() {
    super.initState();
    _portController.text = security.config.port.toString();
    AppServices.instance.peekServer().then((server) async {
      final url = server.isRunning ? await server.serverUrl() : null;
      if (!mounted) return;
      setState(() {
        _server = server;
        _serverUrl = url;
      });
    });
  }

  @override
  void dispose() {
    _portController.dispose();
    super.dispose();
  }

  void _notify(String message, {bool isError = false}) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _messageIsError = isError;
    });
  }

  Future<void> _toggleServer() async {
    final server = _server;
    if (server == null || _busy) return;
    setState(() => _busy = true);
    try {
      if (server.isRunning) {
        await server.stop();
        _serverUrl = null;
        _notify('Peek PC 服务已停止');
        widget.appState.addActivity(
            source: 'SYSTEM',
            title: 'Peek PC',
            value: '服务已停止',
            accent: ToolAccent.blue);
      } else {
        security.setConfig(PeekServerConfig(
          listenScope: security.config.listenScope,
          port: int.tryParse(_portController.text.trim()) ??
              security.config.port,
        ));
        await server.start();
        AppServices.instance.usageTracker.start();
        _serverUrl = await server.serverUrl();
        _notify('服务已启动，手机浏览器打开下方地址即可连接');
        widget.appState.addActivity(
            source: 'SYSTEM',
            title: 'Peek PC',
            value: '服务已启动 $_serverUrl',
            accent: ToolAccent.blue);
      }
    } on PeekSecurityException catch (error) {
      _notify(error.message, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _generateKey() async {
    final IssuedApiKey issued;
    try {
      issued = security.generateApiKey();
    } on PeekSecurityException catch (error) {
      _notify(error.message, isError: true);
      return;
    }
    setState(() {});
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新的 API 密钥'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('密钥只显示这一次，请立即复制到手机端。旧密钥已全部失效。'),
            const SizedBox(height: 12),
            SelectableText(
              issued.apiKey,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('复制密钥'),
            onPressed: () async {
              await copyText(issued.apiKey);
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }

  String _logTime(int ms) {
    final at = DateTime.fromMillisecondsSinceEpoch(ms);
    String pad(int value) => value.toString().padLeft(2, '0');
    return '${pad(at.month)}-${pad(at.day)} ${pad(at.hour)}:${pad(at.minute)}:${pad(at.second)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final server = _server;
    final running = server?.isRunning ?? false;
    final snapshot = security.snapshot();
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(
                    running ? Icons.wifi_tethering : Icons.wifi_tethering_off,
                    color: running ? const Color(0xFF4ADE80) : theme.hintColor,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(running ? '服务运行中' : '服务已停止',
                            style: theme.textTheme.titleSmall),
                        if (running && _serverUrl != null)
                          Row(children: [
                            Flexible(
                              child: SelectableText(_serverUrl!,
                                  style: theme.textTheme.bodySmall),
                            ),
                            IconButton(
                              iconSize: 14,
                              tooltip: '复制地址',
                              icon: const Icon(Icons.copy),
                              onPressed: () => copyText(_serverUrl!),
                            ),
                          ])
                        else
                          Text('生成密钥后启动，手机浏览器访问服务地址即可查看',
                              style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    icon: Icon(running ? Icons.stop : Icons.play_arrow,
                        size: 18),
                    label: Text(running ? '停止服务' : '启动服务'),
                    onPressed:
                        server == null || _busy ? null : _toggleServer,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('API 密钥', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 6),
                      Text(
                        snapshot.apiKeyConfigured
                            ? '已配置（${_logTime(snapshot.apiKeyCreatedAt ?? 0)} 生成）'
                            : '尚未生成',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.key, size: 16),
                        label: Text(snapshot.apiKeyConfigured
                            ? '重新生成（旧密钥失效）'
                            : '生成密钥'),
                        onPressed: _generateKey,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('监听配置（停止后可修改）',
                          style: theme.textTheme.titleSmall),
                      const SizedBox(height: 8),
                      Row(children: [
                        DropdownButton<String>(
                          value: snapshot.config.listenScope,
                          items: const [
                            DropdownMenuItem(
                                value: 'lan', child: Text('局域网 (lan)')),
                            DropdownMenuItem(
                                value: 'local', child: Text('仅本机 (local)')),
                          ],
                          onChanged: running
                              ? null
                              : (value) {
                                  if (value == null) return;
                                  try {
                                    security.setConfig(PeekServerConfig(
                                        listenScope: value,
                                        port: security.config.port));
                                    setState(() {});
                                  } on PeekSecurityException catch (error) {
                                    _notify(error.message, isError: true);
                                  }
                                },
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 96,
                          child: TextField(
                            controller: _portController,
                            enabled: !running,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: '端口',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ]),
                    ],
                  ),
                ),
              ),
            ),
          ]),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                _message!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _messageIsError
                      ? theme.colorScheme.error
                      : const Color(0xFF4ADE80),
                ),
              ),
            ),
          const SizedBox(height: 4),
          Row(children: [
            Text('连接日志（最多 500 条，保留 30 天）',
                style: theme.textTheme.labelLarge),
            const Spacer(),
            IconButton(
              tooltip: '刷新',
              iconSize: 16,
              icon: const Icon(Icons.refresh),
              onPressed: () => setState(() {}),
            ),
            TextButton(
              child: const Text('清空'),
              onPressed: () {
                try {
                  security.clearLogs();
                } on PeekSecurityException catch (error) {
                  _notify(error.message, isError: true);
                }
                setState(() {});
              },
            ),
          ]),
          Expanded(
            child: snapshot.logs.isEmpty
                ? Center(
                    child:
                        Text('暂无连接记录', style: theme.textTheme.bodySmall))
                : ListView.builder(
                    itemCount: snapshot.logs.length,
                    itemBuilder: (context, index) {
                      final log = snapshot.logs[index];
                      return Row(
                        children: [
                          Icon(
                            log.success
                                ? Icons.check_circle_outline
                                : Icons.error_outline,
                            size: 14,
                            color: log.success
                                ? const Color(0xFF4ADE80)
                                : theme.colorScheme.error,
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 118,
                            child: Text(_logTime(log.timestamp),
                                style: theme.textTheme.labelSmall),
                          ),
                          SizedBox(
                            width: 120,
                            child: Text(log.ip,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall),
                          ),
                          Expanded(
                            child: Text(log.event,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall),
                          ),
                        ],
                      );
                    },
                  ),
          ),
          Text(
            '说明：/api/status 提供 CPU、内存与前台窗口；手机端截图待接入原生屏幕捕获，'
            '仪表盘会显示占位提示。',
            style: theme.textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}
