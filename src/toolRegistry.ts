export type ToolKind = 'window' | 'action' | 'planned';
export type ToolAccent = 'teal' | 'blue' | 'orange' | 'green' | 'pink' | 'purple' | 'red';

export type ToolId =
  | 'timer' | 'json' | 'python' | 'encoder' | 'color' | 'hash' | 'image'
  | 'translator' | 'peek_pc' | 'lucky-wheel'
  | 'timestamp' | 'json-format' | 'url-encode' | 'base64' | 'hash-check'
  | 'batch-rename' | 'sort-rule' | 'duplicate-scan';

export type WindowToolId = Extract<ToolId,
  'timer' | 'json' | 'python' | 'encoder' | 'color' | 'hash' | 'image' |
  'translator' | 'peek_pc' | 'lucky-wheel'
>;

export interface ToolDefinition {
  id: ToolId;
  kind: ToolKind;
  title: string;
  description: string;
  icon: string;
  accent: ToolAccent;
  keywords: string[];
  shortcut?: string;
  defaultSize?: { width: number; height: number; minWidth: number; minHeight: number };
  showInLaunchpad: boolean;
  showInDock: boolean;
}

const windowSize = (width = 900, height = 650, minWidth = 560, minHeight = 420) =>
  ({ width, height, minWidth, minHeight });

export const toolRegistry: ToolDefinition[] = [
  { id: 'json', kind: 'window', title: 'JSON 格式化', description: '美化 JSON 文本并查错', icon: 'data_object', accent: 'orange', keywords: ['json', 'format', 'pretty', '格式化'], shortcut: 'Cmd/Ctrl+J', defaultSize: windowSize(), showInLaunchpad: true, showInDock: true },
  { id: 'python', kind: 'window', title: 'Python 工具集', description: '代码排版与字典转换', icon: 'code', accent: 'blue', keywords: ['python', 'ruff', 'format'], defaultSize: windowSize(), showInLaunchpad: true, showInDock: false },
  { id: 'encoder', kind: 'window', title: '万能编码转换', description: 'Base64、URL 与 Unicode 互转', icon: 'swap_horiz', accent: 'green', keywords: ['base64', 'url', 'unicode', '编码'], defaultSize: windowSize(), showInLaunchpad: true, showInDock: false },
  { id: 'color', kind: 'window', title: '深层取色器', description: 'RGB、HEX 与颜色格式转换', icon: 'colorize', accent: 'pink', keywords: ['color', 'rgb', 'hex', '取色'], defaultSize: windowSize(860, 620), showInLaunchpad: true, showInDock: true },
  { id: 'hash', kind: 'window', title: '哈希校验中心', description: '计算 MD5 与 SHA 系列摘要', icon: 'fingerprint', accent: 'purple', keywords: ['hash', 'sha', 'md5', '校验'], defaultSize: windowSize(), showInLaunchpad: true, showInDock: false },
  { id: 'image', kind: 'window', title: '图片格式工厂', description: '离线转换 PNG、JPG 与 WebP', icon: 'imagesmode', accent: 'orange', keywords: ['image', 'png', 'jpg', 'webp', '图片'], defaultSize: windowSize(), showInLaunchpad: true, showInDock: true },
  { id: 'timer', kind: 'window', title: '生产力时钟', description: '秒表、倒计时与计圈', icon: 'timer', accent: 'red', keywords: ['timer', 'stopwatch', '倒计时', '秒表'], shortcut: 'Cmd/Ctrl+T', defaultSize: windowSize(900, 650, 520, 420), showInLaunchpad: true, showInDock: true },
  { id: 'translator', kind: 'window', title: '多语互译机', description: '常用语言快速互译', icon: 'translate', accent: 'teal', keywords: ['translate', 'language', '翻译'], defaultSize: windowSize(), showInLaunchpad: true, showInDock: true },
  { id: 'peek_pc', kind: 'window', title: 'Peek 远程监视', description: '局域网硬件状态与隐私截图', icon: 'desktop_windows', accent: 'blue', keywords: ['peek', 'remote', 'monitor', '监视'], defaultSize: windowSize(980, 700, 680, 500), showInLaunchpad: true, showInDock: false },
  { id: 'lucky-wheel', kind: 'window', title: '幸运大转盘', description: '多级随机决策与抽取', icon: 'cyclone', accent: 'purple', keywords: ['lucky', 'wheel', 'random', '转盘'], shortcut: 'Cmd/Ctrl+L', defaultSize: windowSize(1180, 760, 760, 560), showInLaunchpad: true, showInDock: false },

  { id: 'timestamp', kind: 'action', title: '复制 Unix 时间戳', description: '复制当前 Unix 时间戳', icon: 'schedule', accent: 'teal', keywords: ['timestamp', 'unix', '时间戳'], showInLaunchpad: false, showInDock: false },
  { id: 'json-format', kind: 'action', title: '格式化剪贴板 JSON', description: '格式化剪贴板 JSON 并复制', icon: 'data_object', accent: 'teal', keywords: ['json', 'clipboard', '剪贴板'], showInLaunchpad: false, showInDock: false },
  { id: 'url-encode', kind: 'action', title: 'URL Encode', description: '编码剪贴板中的 URL 文本', icon: 'link', accent: 'teal', keywords: ['url', 'encode', 'uri'], shortcut: 'Cmd/Ctrl+U', showInLaunchpad: false, showInDock: false },
  { id: 'base64', kind: 'action', title: 'Base64', description: '编码剪贴板文本', icon: 'encrypted', accent: 'teal', keywords: ['base64', 'encode'], shortcut: 'Cmd/Ctrl+B', showInLaunchpad: false, showInDock: false },
  { id: 'hash-check', kind: 'action', title: '剪贴板 SHA-256', description: '计算剪贴板文本的 SHA-256', icon: 'fingerprint', accent: 'blue', keywords: ['hash', 'sha256', 'clipboard'], shortcut: 'Cmd/Ctrl+H', showInLaunchpad: false, showInDock: false },

  { id: 'batch-rename', kind: 'planned', title: '批量重命名', description: '将在 v0.2.6 提供', icon: 'edit_square', accent: 'blue', keywords: ['rename', 'file', 'batch'], showInLaunchpad: false, showInDock: false },
  { id: 'sort-rule', kind: 'planned', title: '规则整理文件', description: '将在 v0.2.6 提供', icon: 'sort', accent: 'blue', keywords: ['sort', 'rule', 'file'], showInLaunchpad: false, showInDock: false },
  { id: 'duplicate-scan', kind: 'planned', title: '重复文件扫描', description: '将在 v0.2.6 提供', icon: 'content_copy', accent: 'blue', keywords: ['duplicate', 'scan', 'file'], showInLaunchpad: false, showInDock: false },
];

export const toolsById = new Map(toolRegistry.map((tool) => [tool.id, tool]));
export const windowTools = toolRegistry.filter((tool): tool is ToolDefinition & { id: WindowToolId } => tool.kind === 'window');
export const commandTools = toolRegistry.filter((tool) => tool.kind !== 'planned');

export function getTool(id: string) {
  return toolsById.get(id as ToolId);
}

export function migrateWindowToolId(id: string): WindowToolId | null {
  const aliases: Record<string, WindowToolId> = {
    'json-format': 'json',
    'hash-check': 'hash',
    'timestamp': 'timer',
  };
  const migrated = aliases[id] ?? id;
  const tool = getTool(migrated);
  return tool?.kind === 'window' ? tool.id as WindowToolId : null;
}
