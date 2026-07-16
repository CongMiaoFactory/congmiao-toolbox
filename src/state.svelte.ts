export type NavItem = {
  title: string;
  caption: string;
  icon: string;
};

export type ToolId =
  | 'timestamp'
  | 'json-format'
  | 'url-encode'
  | 'base64'
  | 'hash-check'
  | 'batch-rename'
  | 'sort-rule'
  | 'duplicate-scan'
  | 'lucky-wheel'
  | 'json'
  | 'python'
  | 'encoder'
  | 'color'
  | 'hash'
  | 'image'
  | 'timer'
  | 'translator'
  | 'peek_pc';


export type ToolCommand = {
  id: ToolId;
  title: string;
  subtitle: string;
  shortcut: string;
  icon: string;
  accent: 'teal' | 'blue';
  keywords: string[];
};

export type ActivityEntry = {
  source: 'TEXT' | 'FILE' | 'SYSTEM';
  title: string;
  value: string;
  meta: string;
  accent: 'teal' | 'blue';
};

export type SettingsGroup = {
  title: string;
  items: string[];
};

export function formatMeta() {
  return new Date().toLocaleTimeString('zh-CN', {
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: false,
  });
}



export const navItems: NavItem[] = [
  { title: '仪表盘', caption: '添加小组件 / 快捷跳转', icon: 'dashboard' },
  { title: '全部工具', caption: '工具集列表', icon: 'apps' },
  { title: '使用时长', caption: '应用屏幕使用时间', icon: 'schedule' },
];

export const commands: ToolCommand[] = [
  {
    id: 'timestamp',
    title: 'Timestamp Convert',
    subtitle: '复制当前 Unix 时间戳或处理拖拽文件',
    shortcut: 'Cmd/Ctrl+T',
    icon: 'schedule',
    accent: 'teal',
    keywords: ['timestamp', 'unix', 'time', 'convert', '日期', '时间戳'],
  },
  {
    id: 'json-format',
    title: 'JSON Format',
    subtitle: '读取剪贴板 JSON 并格式化复制',
    shortcut: 'Cmd/Ctrl+J',
    icon: 'data_object',
    accent: 'teal',
    keywords: ['json', 'format', 'pretty', 'clipboard', '格式化'],
  },
  {
    id: 'url-encode',
    title: 'URL Encode',
    subtitle: '编码剪贴板中的 URL 文本',
    shortcut: 'Cmd/Ctrl+U',
    icon: 'link',
    accent: 'teal',
    keywords: ['url', 'encode', 'query', 'uri'],
  },
  {
    id: 'base64',
    title: 'Base64',
    subtitle: '对剪贴板文本进行 Base64 编码',
    shortcut: 'Cmd/Ctrl+B',
    icon: 'encrypted',
    accent: 'teal',
    keywords: ['base64', 'encode', 'text'],
  },
  {
    id: 'hash-check',
    title: 'Hash Check',
    subtitle: '计算剪贴板文本的 SHA-256',
    shortcut: 'Cmd/Ctrl+H',
    icon: 'fingerprint',
    accent: 'blue',
    keywords: ['hash', 'sha', 'sha256', 'checksum'],
  },
  {
    id: 'batch-rename',
    title: 'Batch Rename',
    subtitle: '文件重命名工作台入口',
    shortcut: 'Cmd/Ctrl+R',
    icon: 'edit_square',
    accent: 'blue',
    keywords: ['rename', 'file', 'batch'],
  },
  {
    id: 'sort-rule',
    title: 'Sort by Rule',
    subtitle: '按规则整理文件的入口',
    shortcut: 'Cmd/Ctrl+S',
    icon: 'sort',
    accent: 'blue',
    keywords: ['sort', 'rule', 'file', 'organize'],
  },
  {
    id: 'duplicate-scan',
    title: 'Duplicate Scan',
    subtitle: '重复文件扫描入口',
    shortcut: 'Cmd/Ctrl+D',
    icon: 'content_copy',
    accent: 'blue',
    keywords: ['duplicate', 'scan', 'file'],
  },
  {
    id: 'lucky-wheel',
    title: 'Lucky Wheel',
    subtitle: '多层大转盘，支持大类/小类多级随机',
    shortcut: 'Cmd/Ctrl+L',
    icon: 'cyclone',
    accent: 'blue',
    keywords: ['lucky', 'wheel', 'random', 'roll', '转盘', '幸运'],
  },
];


export const settingsGroups: SettingsGroup[] = [
  { title: 'Stack', items: ['Svelte 5', 'Tailwind-free Custom UI', 'Tauri 2', 'Bun'] },
  { title: 'Automation', items: ['Cmd/Ctrl+K', 'Clipboard Watch', 'Drag to Run'] },
  { title: 'Window', items: ['Single Page', 'Collapsible Sidebar', 'No Scroll'] },
];

export type WindowData = {
  id: string;
  toolId: ToolId;
  title: string;
  x: number;
  y: number;
  width: number;
  height: number;
  isMinimized: boolean;
  isMaximized: boolean;
  zIndex: number;
};

export class AppState {
  appVersion = $state('0.1.0');
  theme = $state<'dark' | 'light'>('light');
  bgImageUrl = $state('https://images.unsplash.com/photo-1558591710-4b4a1ae0f04d?q=80&w=2574&auto=format&fit=crop');
  bgBlur = $state(0);
  sidebarCollapsed = $state(true);
  activeNavIndex = $state(0);
  activeToolId = $state<string | null>(null);
  settingsOpen = $state(false);
  commandOpen = $state(false);
  commandQuery = $state('');
  commandIndex = $state(0);

  currentUnix = $state(Math.floor(Date.now() / 1000));
  clipboardJsonReady = $state(false);
  clipboardJsonHint = $state('剪贴板暂未检测到 JSON');
  clipboardJsonPreview = $state('{ ... }');
  timestampDropActive = $state(false);
  timestampFlash = $state(false);
  jsonFlash = $state(false);
  activeToolPulse = $state<ToolId | null>(null);

  recentActivity = $state<ActivityEntry[]>([
    {
      source: 'SYSTEM',
      title: 'Workspace Ready',
      value: '等待零点击交互',
      meta: formatMeta(),
      accent: 'teal',
    },
    {
      source: 'TEXT',
      title: 'JSON Watch',
      value: '监听剪贴板内容',
      meta: formatMeta(),
      accent: 'teal',
    },
    {
      source: 'FILE',
      title: 'Drop to Run',
      value: '拖拽文件到 Timestamp',
      meta: formatMeta(),
      accent: 'blue',
    },
  ]);

  windows = $state<WindowData[]>([]);
  activeWindowId = $state<string | null>(null);

  openFloatingWindow(toolId: ToolId | string) {
    let title = '工具';
    const cmd = commands.find(c => c.id === toolId);
    if (cmd) {
      title = cmd.title;
    } else {
      // 补充缺失的 title
      const fallbackTitles: Record<string, string> = {
        'json': 'JSON 格式化',
        'python': 'Python 工具集',
        'encoder': '万能编码转换',
        'color': '深层取色器',
        'hash': '哈希校验',
        'image': '图片格式工厂',
        'timer': '生产力时钟',
        'translator': '多语互译机',
        'peek_pc': 'Peek 远程监视',
        'lucky-wheel': '幸运大转盘'
      };
      if (fallbackTitles[toolId]) title = fallbackTitles[toolId];
    }
    
    const existing = this.windows.find(w => w.toolId === toolId);
    if (existing) {
      this.focusWindow(existing.id);
      return;
    }

    const id = crypto.randomUUID();
    const newWindow: WindowData = {
      id,
      toolId: toolId as ToolId,
      title,
      x: 150 + this.windows.length * 30,
      y: 100 + this.windows.length * 30,
      width: 900,
      height: 650,
      isMinimized: false,
      isMaximized: false,
      zIndex: this.windows.length + 10,
    };
    this.windows.push(newWindow);
    this.focusWindow(id);
  }

  closeWindow(id: string) {
    this.windows = this.windows.filter(w => w.id !== id);
    if (this.activeWindowId === id) {
      this.activeWindowId = null;
    }
  }

  focusWindow(id: string) {
    this.activeWindowId = id;
    const maxZIndex = Math.max(0, ...this.windows.map(w => w.zIndex));
    const win = this.windows.find(w => w.id === id);
    if (win) {
      win.zIndex = maxZIndex + 1;
    }
  }

  addActivity(entry: Omit<ActivityEntry, 'meta'>) {
    this.recentActivity = [{ ...entry, meta: formatMeta() }, ...this.recentActivity].slice(0, 4);
  }

  pulseTool(id: ToolId) {
    this.activeToolPulse = id;
    window.setTimeout(() => {
      if (this.activeToolPulse === id) {
        this.activeToolPulse = null;
      }
    }, 900);
  }

  flashTimestampTile() {
    this.timestampFlash = true;
    this.pulseTool('timestamp');
    window.setTimeout(() => {
      this.timestampFlash = false;
    }, 700);
  }

  flashJsonTile() {
    this.jsonFlash = true;
    this.pulseTool('json-format');
    window.setTimeout(() => {
      this.jsonFlash = false;
    }, 900);
  }

  toggleTheme() {
    this.theme = this.theme === 'dark' ? 'light' : 'dark';
    document.documentElement.setAttribute('data-theme', this.theme);
  }
}

export const appState = new AppState();
