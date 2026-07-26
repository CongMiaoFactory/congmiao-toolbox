import 'package:flutter/material.dart';

import '../core/app_state.dart';
import 'color_tool.dart';
import 'encoder_tool.dart';
import 'hash_tool.dart';
import 'json_tool.dart';
import 'lucky_wheel_tool.dart';
import 'placeholder_tool.dart';
import 'timer_tool.dart';

/// Mirror of `src/windowComponents.ts`: one body builder per window tool.
/// Tools that still need the Rust backend get an explanatory placeholder.
final Map<String, Widget Function(AppState appState)> windowToolBuilders = {
  'json': (appState) => JsonTool(appState: appState),
  'encoder': (appState) => EncoderTool(appState: appState),
  'hash': (appState) => HashTool(appState: appState),
  'color': (appState) => ColorTool(appState: appState),
  'timer': (appState) => TimerTool(appState: appState),
  'lucky-wheel': (appState) => LuckyWheelTool(appState: appState),
  'python': (appState) => const PlaceholderTool(
        toolId: 'python',
        note: '原版通过 @astral-sh/ruff-wasm-web 在 WebView 内排版代码。'
            'Flutter 版可改为调用本机 ruff 可执行文件（Process.run）或等价 Dart 实现，'
            '列入下一里程碑。',
      ),
  'image': (appState) => const PlaceholderTool(
        toolId: 'image',
        note: '原版使用浏览器 Canvas 离线转换 PNG/JPG/WebP。'
            'Flutter 版计划采用 package:image 的纯 Dart 编解码实现，列入下一里程碑。',
      ),
  'translator': (appState) => const PlaceholderTool(
        toolId: 'translator',
        note: '原版调用在线翻译接口。移植时需要确认接口与密钥的存放方式，'
            '列入下一里程碑。',
      ),
  'peek_pc': (appState) => const PlaceholderTool(
        toolId: 'peek_pc',
        note: '原版由 Rust (src-tauri/src/peek_server) 提供局域网 HTTP 服务、'
            'API Key 鉴权、失败限流、连接日志与隐私截图。'
            'Flutter 版计划用 dart:io HttpServer 复刻同一套接口与移动端仪表盘，'
            '是后端移植中优先级最高的一项。',
      ),
  'batch-rename': (appState) => const PlaceholderTool(
        toolId: 'batch-rename',
        note: '原版由 Rust (file_tools.rs) 提供预览、执行与撤销。'
            'Flutter 版计划用 dart:io 复刻同样的“先预览后执行 + 操作历史撤销”流程。',
      ),
  'sort-rule': (appState) => const PlaceholderTool(
        toolId: 'sort-rule',
        note: '原版由 Rust (file_tools.rs) 按类型/日期/大小生成安全整理计划。'
            '与批量重命名共用同一套 dart:io 执行/撤销框架，列入文件工具里程碑。',
      ),
  'duplicate-scan': (appState) => const PlaceholderTool(
        toolId: 'duplicate-scan',
        note: '原版由 Rust (file_tools.rs) 分阶段哈希（大小 → 头部 → 全量）生成只读报告。'
            'Flutter 版计划用 Isolate + crypto 实现同样的分阶段扫描。',
      ),
};
