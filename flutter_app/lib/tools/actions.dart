import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_state.dart';
import '../core/launcher.dart';
import '../core/tool_registry.dart';

/// Port of the clipboard quick actions in `src/tools.ts`.
Future<bool> copyText(String text) async {
  try {
    await Clipboard.setData(ClipboardData(text: text));
    return true;
  } catch (_) {
    return false;
  }
}

Future<String> readClipboardText() async {
  try {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    return data?.text ?? '';
  } catch (_) {
    return '';
  }
}

Future<void> runTimestampAction(AppState appState) async {
  final unix = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final copied = await copyText('$unix');
  appState.addActivity(
    source: 'TEXT',
    title: 'Timestamp Copied',
    value: copied ? '$unix' : '复制失败',
    accent: ToolAccent.teal,
  );
}

Future<void> runJsonFormatAction(AppState appState) async {
  final text = await readClipboardText();
  if (text.isEmpty) {
    appState.addActivity(
        source: 'TEXT', title: 'JSON Format', value: '剪贴板为空');
    return;
  }
  try {
    final parsed = jsonDecode(text);
    final pretty = const JsonEncoder.withIndent('  ').convert(parsed);
    final copied = await copyText(pretty);
    appState.addActivity(
      source: 'TEXT',
      title: 'JSON Format',
      value: copied ? '${pretty.length} chars copied' : '格式化完成',
    );
  } on FormatException {
    appState.addActivity(
        source: 'TEXT', title: 'JSON Format', value: '不是合法 JSON');
  }
}

Future<void> runUrlEncodeAction(AppState appState) async {
  final text = await readClipboardText();
  if (text.isEmpty) {
    appState.addActivity(source: 'TEXT', title: 'URL Encode', value: '剪贴板为空');
    return;
  }
  final copied = await copyText(Uri.encodeComponent(text));
  appState.addActivity(
    source: 'TEXT',
    title: 'URL Encode',
    value: copied ? '结果已复制' : '编码完成',
  );
}

Future<void> runBase64Action(AppState appState) async {
  final text = await readClipboardText();
  if (text.isEmpty) {
    appState.addActivity(source: 'TEXT', title: 'Base64', value: '剪贴板为空');
    return;
  }
  final copied = await copyText(base64Encode(utf8.encode(text)));
  appState.addActivity(
    source: 'TEXT',
    title: 'Base64',
    value: copied ? '结果已复制' : '编码完成',
  );
}

Future<void> runHashCheckAction(AppState appState) async {
  final text = await readClipboardText();
  if (text.isEmpty) {
    appState.addActivity(
        source: 'FILE',
        title: 'Hash Check',
        value: '剪贴板为空',
        accent: ToolAccent.blue);
    return;
  }
  final hash = sha256.convert(utf8.encode(text)).toString();
  final copied = await copyText(hash);
  appState.addActivity(
    source: 'FILE',
    title: 'Hash Check',
    value: copied
        ? '${hash.substring(0, 12)}... copied'
        : hash.substring(0, 18),
    accent: ToolAccent.blue,
  );
}

/// Entry point matching `runTool` for both window and action tools.
Future<void> runTool(AppState appState, String id) async {
  final tool = getTool(id);
  if (tool == null) return;
  appState.recordToolUsage(id);
  if (tool.kind == ToolKind.window) {
    appState.openFloatingWindow(id);
    appState.setActiveNavIndex(0);
    appState.addActivity(
      source: 'SYSTEM',
      title: tool.title,
      value: '已打开工具窗口',
      accent: ToolAccent.blue,
    );
    return;
  }
  switch (id) {
    case 'timestamp':
      await runTimestampAction(appState);
    case 'json-format':
      await runJsonFormatAction(appState);
    case 'url-encode':
      await runUrlEncodeAction(appState);
    case 'base64':
      await runBase64Action(appState);
    case 'hash-check':
      await runHashCheckAction(appState);
  }
}

/// Starts an instant countdown from a `> timer 10m` launcher command and
/// opens the productivity clock, mirroring the original palette behavior.
void startQuickCountdown(AppState appState, int seconds) {
  final now = DateTime.now().millisecondsSinceEpoch;
  final countdown = appState.timers.countdown;
  countdown.inputMinutes =
      (seconds / 60).clamp(1, 1440).toDouble();
  countdown.totalMs = seconds * 1000.0;
  countdown.remainingMs = seconds * 1000.0;
  countdown.running = true;
  countdown.targetAt = now + seconds * 1000;
  appState.timers.selectedMode = 'countdown';
  appState.markTimersChanged();
  appState.openFloatingWindow('timer');
  appState.addActivity(
    source: 'SYSTEM',
    title: '快速倒计时',
    value: '$seconds 秒倒计时已开始',
    accent: ToolAccent.blue,
  );
}

Future<void> executeLauncherResult(
    AppState appState, LauncherResult result) async {
  switch (result.kind) {
    case LauncherResultKind.tool:
      await runTool(appState, result.toolId!);
    case LauncherResultKind.workspace:
      appState.applyWorkspaceTemplate(result.templateId!);
      appState.addActivity(
        source: 'SYSTEM',
        title: '工作区模板',
        value: '已应用 ${result.title}',
        accent: ToolAccent.blue,
      );
    case LauncherResultKind.todo:
      appState.addTodo(result.value!);
      appState.addActivity(
          source: 'TEXT', title: '待办', value: '已添加：${result.value}');
    case LauncherResultKind.timer:
      startQuickCountdown(appState, result.seconds!);
    case LauncherResultKind.calculation:
      final copied = await copyText(result.value!);
      appState.addActivity(
        source: 'TEXT',
        title: '计算器',
        value: copied ? '${result.value} 已复制' : result.value!,
      );
    case LauncherResultKind.url:
      await launchUrl(Uri.parse(result.value!),
          mode: LaunchMode.externalApplication);
    case LauncherResultKind.search:
      final query = Uri.encodeComponent(result.value!);
      await launchUrl(Uri.parse('https://www.google.com/search?q=$query'),
          mode: LaunchMode.externalApplication);
  }
}
