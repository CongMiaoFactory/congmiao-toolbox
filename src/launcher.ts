import type { ToolAccent, ToolDefinition, ToolId } from './toolRegistry';
import type { RecentToolUsage, WorkspaceTemplate } from './workspace';

export type LauncherResult = {
  id: string;
  kind: 'tool' | 'workspace' | 'todo' | 'timer' | 'url' | 'search' | 'calculation';
  title: string;
  description: string;
  icon: string;
  accent: ToolAccent;
  shortcut?: string;
  toolId?: ToolId;
  templateId?: string;
  value?: string;
  seconds?: number;
};

export function fuzzyScore(query: string, target: string) {
  if (!query) return 1;
  let score = 0;
  let targetIndex = 0;
  let streak = 0;
  for (const char of query) {
    const foundAt = target.indexOf(char, targetIndex);
    if (foundAt === -1) return -1;
    streak = foundAt === targetIndex ? streak + 1 : 1;
    score += 3 + streak;
    if (foundAt === 0) score += 4;
    targetIndex = foundAt + 1;
  }
  return score;
}

function parseTimerCommand(query: string) {
  const match = query.match(/^>\s*timer\s+(\d+(?:\.\d+)?)\s*([smh]?)$/i);
  if (!match) return null;
  const value = Number(match[1]);
  const factor = match[2].toLowerCase() === 'h' ? 3600 : match[2].toLowerCase() === 's' ? 1 : 60;
  const seconds = Math.round(value * factor);
  return seconds >= 1 && seconds <= 86_400 ? seconds : null;
}

function normalizeUrl(query: string) {
  const trimmed = query.trim();
  if (/^https?:\/\//i.test(trimmed)) {
    try {
      const url = new URL(trimmed);
      return ['http:', 'https:'].includes(url.protocol) ? url.toString() : null;
    } catch { return null; }
  }
  if (/^[\w-]+(?:\.[\w-]+)+(?:[/?#].*)?$/i.test(trimmed)) {
    try { return new URL(`https://${trimmed}`).toString(); } catch { return null; }
  }
  return null;
}

class Calculator {
  private index = 0;
  constructor(private readonly source: string) {}
  parse() {
    const value = this.expression();
    this.space();
    if (this.index !== this.source.length || !Number.isFinite(value)) throw new Error('invalid expression');
    return value;
  }
  private expression(): number {
    let value = this.term();
    while (true) {
      this.space();
      if (this.take('+')) value += this.term();
      else if (this.take('-')) value -= this.term();
      else return value;
    }
  }
  private term(): number {
    let value = this.factor();
    while (true) {
      this.space();
      if (this.take('*')) value *= this.factor();
      else if (this.take('/')) value /= this.factor();
      else if (this.take('%')) value %= this.factor();
      else return value;
    }
  }
  private factor(): number {
    this.space();
    if (this.take('+')) return this.factor();
    if (this.take('-')) return -this.factor();
    if (this.take('(')) {
      const value = this.expression();
      this.space();
      if (!this.take(')')) throw new Error('missing parenthesis');
      return value;
    }
    const match = this.source.slice(this.index).match(/^(?:\d+(?:\.\d*)?|\.\d+)/);
    if (!match) throw new Error('number expected');
    this.index += match[0].length;
    return Number(match[0]);
  }
  private take(value: string) {
    if (this.source[this.index] !== value) return false;
    this.index += 1;
    return true;
  }
  private space() {
    while (/\s/.test(this.source[this.index] ?? '')) this.index += 1;
  }
}

export function calculate(query: string) {
  const source = query.trim().replace(/^=/, '').trim();
  if (!source || source.length > 80 || !/[+\-*/%()]/.test(source)) return null;
  if (!/^[\d\s.+\-*/%()]+$/.test(source)) return null;
  try {
    const value = new Calculator(source).parse();
    return Number.isFinite(value) ? value : null;
  } catch { return null; }
}

export function buildLauncherResults(
  rawQuery: string,
  tools: ToolDefinition[],
  templates: WorkspaceTemplate[],
  favorites: ToolId[],
  recentTools: RecentToolUsage[],
): LauncherResult[] {
  const query = rawQuery.trim();
  const normalized = query.toLowerCase();
  const recent = new Map(recentTools.map((item) => [item.id, item]));
  const results: Array<LauncherResult & { score: number }> = [];

  const timerSeconds = parseTimerCommand(query);
  if (timerSeconds !== null) results.push({
    id: `timer:${timerSeconds}`, kind: 'timer', title: `启动 ${timerSeconds >= 60 ? `${timerSeconds / 60} 分钟` : `${timerSeconds} 秒`}倒计时`,
    description: '打开生产力时钟并立即开始倒计时', icon: 'timer', accent: 'red', seconds: timerSeconds, score: 10_000,
  });
  const todo = query.match(/^>\s*todo\s+(.+)$/i)?.[1]?.trim();
  if (todo) results.push({ id: `todo:${todo}`, kind: 'todo', title: `添加待办：${todo}`, description: '添加到桌面待办列表', icon: 'add_task', accent: 'teal', value: todo, score: 10_000 });
  if (/^>\s*peek\s*$/i.test(query)) results.push({ id: 'command:peek', kind: 'tool', toolId: 'peek_pc', title: '打开 Peek PC', description: '打开局域网监视工具', icon: 'desktop_windows', accent: 'blue', score: 10_000 });

  const workspaceQuery = query.match(/^>\s*workspace(?:\s+(.+))?$/i)?.[1]?.trim().toLowerCase();
  for (const template of templates) {
    const score = workspaceQuery !== undefined
      ? (workspaceQuery ? fuzzyScore(workspaceQuery, template.name.toLowerCase()) : 50)
      : fuzzyScore(normalized, `${template.name} 工作区 workspace`);
    if (score >= 0) results.push({
      id: `workspace:${template.id}`, kind: 'workspace', templateId: template.id,
      title: template.name, description: `${template.desktop.windows.length} 个工具窗口 · 工作区模板`,
      icon: 'space_dashboard', accent: 'purple', score: score + (workspaceQuery !== undefined ? 500 : 0),
    });
  }

  if (!query.startsWith('>')) {
    for (const tool of tools) {
      const haystack = [tool.title, tool.description, tool.shortcut ?? '', ...tool.keywords].join(' ').toLowerCase();
      const score = fuzzyScore(normalized, haystack);
      if (score < 0) continue;
      const usage = recent.get(tool.id);
      const favoriteBoost = favorites.includes(tool.id) ? 200 : 0;
      const recentBoost = !query && usage ? Math.min(80, usage.useCount * 4) : 0;
      results.push({
        id: `tool:${tool.id}`, kind: 'tool', toolId: tool.id, title: tool.title,
        description: tool.description, icon: tool.icon, accent: tool.accent, shortcut: tool.shortcut,
        score: score + favoriteBoost + recentBoost,
      });
    }

    const calculation = calculate(query);
    if (calculation !== null) results.push({
      id: `calculation:${query}`, kind: 'calculation', title: `${calculation}`,
      description: '按 Enter 复制计算结果', icon: 'calculate', accent: 'green', value: `${calculation}`, score: 9000,
    });
    const url = normalizeUrl(query);
    if (url) results.push({
      id: `url:${url}`, kind: 'url', title: `打开 ${new URL(url).host}`,
      description: url, icon: 'open_in_browser', accent: 'blue', value: url, score: 8500,
    }); else if (query.length >= 2) results.push({
      id: `search:${query}`, kind: 'search', title: `搜索“${query}”`,
      description: '使用默认浏览器和搜索引擎', icon: 'travel_explore', accent: 'blue', value: query, score: -10,
    });
  }

  return results.sort((a, b) => b.score - a.score).slice(0, 30).map(({ score: _score, ...result }) => result);
}
