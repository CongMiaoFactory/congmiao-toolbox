import 'package:flutter/material.dart';

import 'tool_registry.dart';
import 'workspace.dart';

/// Mirror of `src/launcher.ts`: fuzzy scoring, safe calculator, URL
/// normalization and the quick-launcher result builder.
enum LauncherResultKind { tool, workspace, todo, timer, url, search, calculation }

class LauncherResult {
  const LauncherResult({
    required this.id,
    required this.kind,
    required this.title,
    required this.description,
    required this.icon,
    required this.accent,
    this.shortcut,
    this.toolId,
    this.templateId,
    this.value,
    this.seconds,
  });

  final String id;
  final LauncherResultKind kind;
  final String title;
  final String description;
  final IconData icon;
  final ToolAccent accent;
  final String? shortcut;
  final String? toolId;
  final String? templateId;
  final String? value;
  final int? seconds;
}

class _ScoredResult {
  _ScoredResult(this.result, this.score);

  final LauncherResult result;
  final double score;
}

double fuzzyScore(String query, String target) {
  if (query.isEmpty) return 1;
  var score = 0.0;
  var targetIndex = 0;
  var streak = 0;
  for (final rune in query.runes) {
    final char = String.fromCharCode(rune);
    final foundAt = target.indexOf(char, targetIndex);
    if (foundAt == -1) return -1;
    streak = foundAt == targetIndex ? streak + 1 : 1;
    score += 3 + streak;
    if (foundAt == 0) score += 4;
    targetIndex = foundAt + 1;
  }
  return score;
}

final _timerCommand = RegExp(r'^>\s*timer\s+(\d+(?:\.\d+)?)\s*([smh]?)$',
    caseSensitive: false);

int? parseTimerCommand(String query) {
  final match = _timerCommand.firstMatch(query);
  if (match == null) return null;
  final value = double.tryParse(match.group(1)!);
  if (value == null) return null;
  final unit = (match.group(2) ?? '').toLowerCase();
  final factor = unit == 'h' ? 3600 : (unit == 's' ? 1 : 60);
  final seconds = (value * factor).round();
  return seconds >= 1 && seconds <= 86400 ? seconds : null;
}

final _bareDomain =
    RegExp(r'^[\w-]+(?:\.[\w-]+)+(?:[/?#].*)?$', caseSensitive: false);

String? normalizeUrl(String query) {
  final trimmed = query.trim();
  if (RegExp(r'^https?://', caseSensitive: false).hasMatch(trimmed)) {
    final url = Uri.tryParse(trimmed);
    if (url == null || !(url.scheme == 'http' || url.scheme == 'https')) {
      return null;
    }
    return url.host.isEmpty ? null : url.toString();
  }
  if (_bareDomain.hasMatch(trimmed)) {
    final url = Uri.tryParse('https://$trimmed');
    return url == null || url.host.isEmpty ? null : url.toString();
  }
  return null;
}

/// Recursive-descent arithmetic parser identical to the original launcher's
/// eval-free calculator (`+ - * / %`, parentheses, unary signs).
class _Calculator {
  _Calculator(this.source);

  final String source;
  int _index = 0;

  double parse() {
    final value = _expression();
    _space();
    if (_index != source.length || !value.isFinite) {
      throw const FormatException('invalid expression');
    }
    return value;
  }

  double _expression() {
    var value = _term();
    while (true) {
      _space();
      if (_take('+')) {
        value += _term();
      } else if (_take('-')) {
        value -= _term();
      } else {
        return value;
      }
    }
  }

  double _term() {
    var value = _factor();
    while (true) {
      _space();
      if (_take('*')) {
        value *= _factor();
      } else if (_take('/')) {
        value /= _factor();
      } else if (_take('%')) {
        // JS-style remainder (sign follows the dividend), unlike Dart's `%`.
        value = value.remainder(_factor());
      } else {
        return value;
      }
    }
  }

  double _factor() {
    _space();
    if (_take('+')) return _factor();
    if (_take('-')) return -_factor();
    if (_take('(')) {
      final value = _expression();
      _space();
      if (!_take(')')) throw const FormatException('missing parenthesis');
      return value;
    }
    final match = RegExp(r'^(?:\d+(?:\.\d*)?|\.\d+)')
        .firstMatch(source.substring(_index));
    if (match == null) throw const FormatException('number expected');
    _index += match.group(0)!.length;
    return double.parse(match.group(0)!);
  }

  bool _take(String value) {
    if (_index >= source.length || source[_index] != value) return false;
    _index += 1;
    return true;
  }

  void _space() {
    while (_index < source.length &&
        RegExp(r'\s').hasMatch(source[_index])) {
      _index += 1;
    }
  }
}

double? calculate(String query) {
  var source = query.trim();
  if (source.startsWith('=')) source = source.substring(1).trim();
  if (source.isEmpty || source.length > 80) return null;
  if (!RegExp(r'[+\-*/%()]').hasMatch(source)) return null;
  if (!RegExp(r'^[\d\s.+\-*/%()]+$').hasMatch(source)) return null;
  try {
    final value = _Calculator(source).parse();
    return value.isFinite ? value : null;
  } on FormatException {
    return null;
  }
}

String formatCalculation(double value) {
  if (value == value.roundToDouble() && value.abs() < 1e15) {
    return value.round().toString();
  }
  return value.toString();
}

List<LauncherResult> buildLauncherResults(
  String rawQuery,
  List<ToolDefinition> tools,
  List<WorkspaceTemplate> templates,
  List<String> favorites,
  List<RecentToolUsage> recentTools,
) {
  final query = rawQuery.trim();
  final normalized = query.toLowerCase();
  final recent = {for (final item in recentTools) item.id: item};
  final results = <_ScoredResult>[];

  final timerSeconds = parseTimerCommand(query);
  if (timerSeconds != null) {
    final label = timerSeconds >= 60
        ? '${formatCalculation(timerSeconds / 60)} 分钟'
        : '$timerSeconds 秒';
    results.add(_ScoredResult(
      LauncherResult(
        id: 'timer:$timerSeconds',
        kind: LauncherResultKind.timer,
        title: '启动 $label倒计时',
        description: '打开生产力时钟并立即开始倒计时',
        icon: Icons.timer,
        accent: ToolAccent.red,
        seconds: timerSeconds,
      ),
      10000,
    ));
  }

  final todoMatch =
      RegExp(r'^>\s*todo\s+(.+)$', caseSensitive: false).firstMatch(query);
  final todo = todoMatch?.group(1)?.trim();
  if (todo != null && todo.isNotEmpty) {
    results.add(_ScoredResult(
      LauncherResult(
        id: 'todo:$todo',
        kind: LauncherResultKind.todo,
        title: '添加待办：$todo',
        description: '添加到桌面待办列表',
        icon: Icons.add_task,
        accent: ToolAccent.teal,
        value: todo,
      ),
      10000,
    ));
  }

  if (RegExp(r'^>\s*peek\s*$', caseSensitive: false).hasMatch(query)) {
    results.add(_ScoredResult(
      const LauncherResult(
        id: 'command:peek',
        kind: LauncherResultKind.tool,
        toolId: 'peek_pc',
        title: '打开 Peek PC',
        description: '打开局域网监视工具',
        icon: Icons.desktop_windows,
        accent: ToolAccent.blue,
      ),
      10000,
    ));
  }

  final workspaceMatch = RegExp(r'^>\s*workspace(?:\s+(.+))?$',
          caseSensitive: false)
      .firstMatch(query);
  final workspaceQuery =
      workspaceMatch == null ? null : (workspaceMatch.group(1)?.trim().toLowerCase() ?? '');
  for (final template in templates) {
    final score = workspaceQuery != null
        ? (workspaceQuery.isNotEmpty
            ? fuzzyScore(workspaceQuery, template.name.toLowerCase())
            : 50.0)
        : fuzzyScore(normalized, '${template.name} 工作区 workspace'.toLowerCase());
    if (score >= 0) {
      results.add(_ScoredResult(
        LauncherResult(
          id: 'workspace:${template.id}',
          kind: LauncherResultKind.workspace,
          templateId: template.id,
          title: template.name,
          description: '${template.desktop.windows.length} 个工具窗口 · 工作区模板',
          icon: Icons.space_dashboard,
          accent: ToolAccent.purple,
        ),
        score + (workspaceQuery != null ? 500 : 0),
      ));
    }
  }

  if (!query.startsWith('>')) {
    for (final tool in tools) {
      final haystack = [
        tool.title,
        tool.description,
        tool.shortcut ?? '',
        ...tool.keywords,
      ].join(' ').toLowerCase();
      final score = fuzzyScore(normalized, haystack);
      if (score < 0) continue;
      final usage = recent[tool.id];
      final favoriteBoost = favorites.contains(tool.id) ? 200.0 : 0.0;
      final recentBoost = query.isEmpty && usage != null
          ? (usage.useCount * 4).clamp(0, 80).toDouble()
          : 0.0;
      results.add(_ScoredResult(
        LauncherResult(
          id: 'tool:${tool.id}',
          kind: LauncherResultKind.tool,
          toolId: tool.id,
          title: tool.title,
          description: tool.description,
          icon: tool.icon,
          accent: tool.accent,
          shortcut: tool.shortcut,
        ),
        score + favoriteBoost + recentBoost,
      ));
    }

    final calculation = calculate(query);
    if (calculation != null) {
      final formatted = formatCalculation(calculation);
      results.add(_ScoredResult(
        LauncherResult(
          id: 'calculation:$query',
          kind: LauncherResultKind.calculation,
          title: formatted,
          description: '按 Enter 复制计算结果',
          icon: Icons.calculate,
          accent: ToolAccent.green,
          value: formatted,
        ),
        9000,
      ));
    }

    final url = normalizeUrl(query);
    if (url != null) {
      results.add(_ScoredResult(
        LauncherResult(
          id: 'url:$url',
          kind: LauncherResultKind.url,
          title: '打开 ${Uri.parse(url).host}',
          description: url,
          icon: Icons.open_in_browser,
          accent: ToolAccent.blue,
          value: url,
        ),
        8500,
      ));
    } else if (query.length >= 2) {
      results.add(_ScoredResult(
        LauncherResult(
          id: 'search:$query',
          kind: LauncherResultKind.search,
          title: '搜索“$query”',
          description: '使用默认浏览器和搜索引擎',
          icon: Icons.travel_explore,
          accent: ToolAccent.blue,
          value: query,
        ),
        -10,
      ));
    }
  }

  results.sort((a, b) => b.score.compareTo(a.score));
  return results.take(30).map((entry) => entry.result).toList();
}
