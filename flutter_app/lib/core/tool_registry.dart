import 'package:flutter/material.dart';

/// Mirror of `src/toolRegistry.ts` from the Tauri/Svelte app.
enum ToolKind { window, action, planned }

enum ToolAccent { teal, blue, orange, green, pink, purple, red }

class ToolWindowSize {
  const ToolWindowSize({
    this.width = 900,
    this.height = 650,
    this.minWidth = 560,
    this.minHeight = 420,
  });

  final double width;
  final double height;
  final double minWidth;
  final double minHeight;
}

class ToolDefinition {
  const ToolDefinition({
    required this.id,
    required this.kind,
    required this.title,
    required this.description,
    required this.icon,
    required this.accent,
    required this.keywords,
    this.shortcut,
    this.defaultSize,
    this.showInLaunchpad = false,
    this.showInDock = false,
    this.ported = true,
  });

  final String id;
  final ToolKind kind;
  final String title;
  final String description;
  final IconData icon;
  final ToolAccent accent;
  final List<String> keywords;
  final String? shortcut;
  final ToolWindowSize? defaultSize;
  final bool showInLaunchpad;
  final bool showInDock;

  /// Whether the tool body is already ported to Flutter. Tools that still
  /// depend on the Rust backend open a placeholder window describing the
  /// porting plan.
  final bool ported;
}

const toolRegistry = <ToolDefinition>[
  ToolDefinition(
    id: 'json',
    kind: ToolKind.window,
    title: 'JSON 格式化',
    description: '美化 JSON 文本并查错',
    icon: Icons.data_object,
    accent: ToolAccent.orange,
    keywords: ['json', 'format', 'pretty', '格式化'],
    shortcut: 'Ctrl+J',
    defaultSize: ToolWindowSize(),
    showInLaunchpad: true,
    showInDock: true,
  ),
  ToolDefinition(
    id: 'python',
    kind: ToolKind.window,
    title: 'Python 工具集',
    description: '代码排版与字典转换',
    icon: Icons.code,
    accent: ToolAccent.blue,
    keywords: ['python', 'ruff', 'format'],
    defaultSize: ToolWindowSize(),
    showInLaunchpad: true,
    ported: false,
  ),
  ToolDefinition(
    id: 'encoder',
    kind: ToolKind.window,
    title: '万能编码转换',
    description: 'Base64、URL 与 Unicode 互转',
    icon: Icons.swap_horiz,
    accent: ToolAccent.green,
    keywords: ['base64', 'url', 'unicode', '编码'],
    defaultSize: ToolWindowSize(),
    showInLaunchpad: true,
  ),
  ToolDefinition(
    id: 'color',
    kind: ToolKind.window,
    title: '深层取色器',
    description: 'RGB、HEX 与颜色格式转换',
    icon: Icons.colorize,
    accent: ToolAccent.pink,
    keywords: ['color', 'rgb', 'hex', '取色'],
    defaultSize: ToolWindowSize(width: 860, height: 620),
    showInLaunchpad: true,
    showInDock: true,
  ),
  ToolDefinition(
    id: 'hash',
    kind: ToolKind.window,
    title: '哈希校验中心',
    description: '计算 MD5 与 SHA 系列摘要',
    icon: Icons.fingerprint,
    accent: ToolAccent.purple,
    keywords: ['hash', 'sha', 'md5', '校验'],
    defaultSize: ToolWindowSize(),
    showInLaunchpad: true,
  ),
  ToolDefinition(
    id: 'image',
    kind: ToolKind.window,
    title: '图片格式工厂',
    description: '离线转换 PNG、JPG 与 WebP',
    icon: Icons.image,
    accent: ToolAccent.orange,
    keywords: ['image', 'png', 'jpg', 'webp', '图片'],
    defaultSize: ToolWindowSize(),
    showInLaunchpad: true,
    showInDock: true,
    ported: false,
  ),
  ToolDefinition(
    id: 'timer',
    kind: ToolKind.window,
    title: '生产力时钟',
    description: '秒表、倒计时与计圈',
    icon: Icons.timer,
    accent: ToolAccent.red,
    keywords: ['timer', 'stopwatch', '倒计时', '秒表'],
    shortcut: 'Ctrl+T',
    defaultSize: ToolWindowSize(width: 900, height: 650, minWidth: 520, minHeight: 420),
    showInLaunchpad: true,
    showInDock: true,
  ),
  ToolDefinition(
    id: 'translator',
    kind: ToolKind.window,
    title: '多语互译机',
    description: '常用语言快速互译',
    icon: Icons.translate,
    accent: ToolAccent.teal,
    keywords: ['translate', 'language', '翻译'],
    defaultSize: ToolWindowSize(),
    showInLaunchpad: true,
    showInDock: true,
    ported: false,
  ),
  ToolDefinition(
    id: 'peek_pc',
    kind: ToolKind.window,
    title: 'Peek 远程监视',
    description: '局域网硬件状态与隐私截图',
    icon: Icons.desktop_windows,
    accent: ToolAccent.blue,
    keywords: ['peek', 'remote', 'monitor', '监视'],
    defaultSize: ToolWindowSize(width: 980, height: 700, minWidth: 680, minHeight: 500),
    showInLaunchpad: true,
    ported: false,
  ),
  ToolDefinition(
    id: 'lucky-wheel',
    kind: ToolKind.window,
    title: '幸运大转盘',
    description: '多级随机决策与抽取',
    icon: Icons.cyclone,
    accent: ToolAccent.purple,
    keywords: ['lucky', 'wheel', 'random', '转盘'],
    shortcut: 'Ctrl+L',
    defaultSize: ToolWindowSize(width: 1180, height: 760, minWidth: 760, minHeight: 560),
    showInLaunchpad: true,
  ),
  ToolDefinition(
    id: 'timestamp',
    kind: ToolKind.action,
    title: '复制 Unix 时间戳',
    description: '复制当前 Unix 时间戳',
    icon: Icons.schedule,
    accent: ToolAccent.teal,
    keywords: ['timestamp', 'unix', '时间戳'],
  ),
  ToolDefinition(
    id: 'json-format',
    kind: ToolKind.action,
    title: '格式化剪贴板 JSON',
    description: '格式化剪贴板 JSON 并复制',
    icon: Icons.data_object,
    accent: ToolAccent.teal,
    keywords: ['json', 'clipboard', '剪贴板'],
  ),
  ToolDefinition(
    id: 'url-encode',
    kind: ToolKind.action,
    title: 'URL Encode',
    description: '编码剪贴板中的 URL 文本',
    icon: Icons.link,
    accent: ToolAccent.teal,
    keywords: ['url', 'encode', 'uri'],
    shortcut: 'Ctrl+U',
  ),
  ToolDefinition(
    id: 'base64',
    kind: ToolKind.action,
    title: 'Base64',
    description: '编码剪贴板文本',
    icon: Icons.enhanced_encryption,
    accent: ToolAccent.teal,
    keywords: ['base64', 'encode'],
    shortcut: 'Ctrl+B',
  ),
  ToolDefinition(
    id: 'hash-check',
    kind: ToolKind.action,
    title: '剪贴板 SHA-256',
    description: '计算剪贴板文本的 SHA-256',
    icon: Icons.fingerprint,
    accent: ToolAccent.blue,
    keywords: ['hash', 'sha256', 'clipboard'],
    shortcut: 'Ctrl+H',
  ),
  ToolDefinition(
    id: 'batch-rename',
    kind: ToolKind.window,
    title: '批量重命名',
    description: '组合规则预览、执行与撤销',
    icon: Icons.drive_file_rename_outline,
    accent: ToolAccent.blue,
    keywords: ['rename', 'file', 'batch', '重命名'],
    defaultSize: ToolWindowSize(width: 1100, height: 740, minWidth: 760, minHeight: 540),
    showInLaunchpad: true,
    ported: false,
  ),
  ToolDefinition(
    id: 'sort-rule',
    kind: ToolKind.window,
    title: '规则整理文件',
    description: '按类型、日期或大小安全整理',
    icon: Icons.sort,
    accent: ToolAccent.green,
    keywords: ['sort', 'rule', 'file', '整理'],
    defaultSize: ToolWindowSize(width: 1100, height: 740, minWidth: 760, minHeight: 540),
    showInLaunchpad: true,
    ported: false,
  ),
  ToolDefinition(
    id: 'duplicate-scan',
    kind: ToolKind.window,
    title: '重复文件扫描',
    description: '分阶段哈希生成只读报告',
    icon: Icons.content_copy,
    accent: ToolAccent.purple,
    keywords: ['duplicate', 'scan', 'file', '重复'],
    defaultSize: ToolWindowSize(width: 1050, height: 720, minWidth: 720, minHeight: 520),
    showInLaunchpad: true,
    ported: false,
  ),
];

final Map<String, ToolDefinition> toolsById = {
  for (final tool in toolRegistry) tool.id: tool,
};

final List<ToolDefinition> windowTools =
    toolRegistry.where((tool) => tool.kind == ToolKind.window).toList();

final List<ToolDefinition> launchpadTools =
    toolRegistry.where((tool) => tool.showInLaunchpad).toList();

ToolDefinition? getTool(String id) => toolsById[id];

/// Legacy floating-window aliases from older workspace snapshots.
String? migrateWindowToolId(String id) {
  const aliases = <String, String>{
    'json-format': 'json',
    'hash-check': 'hash',
    'timestamp': 'timer',
  };
  final migrated = aliases[id] ?? id;
  final tool = getTool(migrated);
  return tool?.kind == ToolKind.window ? tool!.id : null;
}

Color accentColor(ToolAccent accent) {
  switch (accent) {
    case ToolAccent.teal:
      return const Color(0xFF2DD4BF);
    case ToolAccent.blue:
      return const Color(0xFF60A5FA);
    case ToolAccent.orange:
      return const Color(0xFFFB923C);
    case ToolAccent.green:
      return const Color(0xFF4ADE80);
    case ToolAccent.pink:
      return const Color(0xFFF472B6);
    case ToolAccent.purple:
      return const Color(0xFFA78BFA);
    case ToolAccent.red:
      return const Color(0xFFF87171);
  }
}
