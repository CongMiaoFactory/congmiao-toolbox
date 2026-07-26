import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'ids.dart';
import 'persistence.dart';
import 'tool_registry.dart';
import 'workspace.dart';

export 'ids.dart' show generateId;

/// Port of `src/state.svelte.ts`. Svelte runes become a [ChangeNotifier];
/// every mutating method ends with [notifyListeners] plus the same
/// debounced persistence used by the original app.
class ActivityEntry {
  ActivityEntry({
    required this.source,
    required this.title,
    required this.value,
    required this.meta,
    required this.accent,
  });

  final String source; // TEXT | FILE | SYSTEM
  final String title;
  final String value;
  final String meta;
  final ToolAccent accent;
}

class NavItem {
  const NavItem({required this.title, required this.caption, required this.icon});

  final String title;
  final String caption;
  final String icon;
}

const navItems = <NavItem>[
  NavItem(title: '仪表盘', caption: '添加小组件 / 快捷跳转', icon: 'dashboard'),
  NavItem(title: '全部工具', caption: '工具集列表', icon: 'apps'),
  NavItem(title: '使用时长', caption: '应用屏幕使用时间', icon: 'schedule'),
];

class WindowData {
  WindowData({
    required this.id,
    required this.toolId,
    required this.title,
    required this.geometry,
    required this.minWidth,
    required this.minHeight,
    required this.zIndex,
    this.isMinimized = false,
    this.isMaximized = false,
    this.restoreGeometry,
  });

  final String id;
  final String toolId;
  final String title;
  WindowGeometry geometry;
  final double minWidth;
  final double minHeight;
  int zIndex;
  bool isMinimized;
  bool isMaximized;
  WindowGeometry? restoreGeometry;
}

String formatMeta([DateTime? at]) {
  final now = at ?? DateTime.now();
  String pad(int value) => value.toString().padLeft(2, '0');
  return '${pad(now.hour)}:${pad(now.minute)}:${pad(now.second)}';
}

class AppState extends ChangeNotifier {
  AppState({this.persistDelay = const Duration(milliseconds: 250)});

  static const appVersion = '0.1.0-flutter';

  final Duration persistDelay;

  bool ready = false;
  String theme = 'light';
  String bgImageUrl = defaultWallpaper;
  double bgBlur = 0;
  bool sidebarCollapsed = true;
  int activeNavIndex = 0;

  final List<WindowData> windows = [];
  String? activeWindowId;
  final List<TodoItem> todos = [];
  TimerSnapshot timers = defaultTimerSnapshot();
  final List<WorkspaceTemplate> workspaceTemplates = [];
  final List<String> favorites = [];
  final List<RecentToolUsage> recentTools = [];
  String globalShortcut = defaultLauncherPreferences().globalShortcut;

  final List<ActivityEntry> recentActivity = [
    ActivityEntry(
      source: 'SYSTEM',
      title: 'Workspace Ready',
      value: '等待操作',
      meta: formatMeta(),
      accent: ToolAccent.teal,
    ),
  ];

  Viewport _viewport = const Viewport(width: 1366, height: 728);
  Timer? _persistTimer;
  Future<void> _persistQueue = Future<void>.value();

  Viewport get viewport => _viewport;

  /// Updates the desktop viewport (from LayoutBuilder) and clamps windows
  /// back inside it, mirroring `reconcileWindowBounds`.
  void setViewport(Viewport viewport, {bool reconcile = true}) {
    final next = Viewport(
      width: math.max(480, viewport.width),
      height: math.max(360, viewport.height),
    );
    if (next.width == _viewport.width && next.height == _viewport.height) {
      return;
    }
    _viewport = next;
    if (!reconcile) return;
    for (final window in windows) {
      if (window.isMaximized) {
        window.geometry = WindowGeometry(
            x: 0, y: 0, width: _viewport.width, height: _viewport.height);
      } else {
        window.geometry = clampGeometry(window.geometry, _viewport,
            minWidth: window.minWidth, minHeight: window.minHeight);
      }
    }
    schedulePersist();
    notifyListeners();
  }

  Future<void> hydrate() async {
    final workspace = await loadWorkspace();
    if (workspace != null) {
      theme = workspace.preferences.theme;
      bgImageUrl = workspace.preferences.bgImageUrl.isEmpty
          ? defaultWallpaper
          : workspace.preferences.bgImageUrl;
      bgBlur = workspace.preferences.bgBlur.clamp(0, 100).toDouble();
      sidebarCollapsed = workspace.preferences.sidebarCollapsed;
      activeNavIndex = workspace.desktop.activeNavIndex.clamp(0, 2).toInt();

      todos
        ..clear()
        ..addAll(workspace.todos
            .where((todo) => todo.text.trim().isNotEmpty)
            .take(500));
      timers = reconcileTimers(workspace.timers);

      workspaceTemplates
        ..clear()
        ..addAll(workspace.workspaceTemplates
            .where((template) =>
                template.id.isNotEmpty && template.name.isNotEmpty)
            .take(20));

      favorites
        ..clear()
        ..addAll(workspace.launcher.favorites
            .where((id) => getTool(id) != null)
            .take(20));
      final sortedRecents = workspace.launcher.recentTools
          .where((item) => getTool(item.id) != null)
          .toList()
        ..sort((a, b) => b.lastUsedAt.compareTo(a.lastUsedAt));
      recentTools
        ..clear()
        ..addAll(sortedRecents.take(30));
      const allowedShortcuts = [
        'Ctrl+Alt+Space',
        'Ctrl+Shift+Space',
        'Ctrl+Alt+K',
        'Alt+Shift+Space',
      ];
      globalShortcut = allowedShortcuts.contains(workspace.launcher.globalShortcut)
          ? workspace.launcher.globalShortcut
          : defaultLauncherPreferences().globalShortcut;

      windows.clear();
      var restoredActive = false;
      for (final saved in workspace.desktop.windows) {
        final toolId = migrateWindowToolId(saved.toolId);
        final tool = toolId == null ? null : getTool(toolId);
        final size = tool?.defaultSize;
        if (toolId == null || tool == null || size == null) continue;
        final geometry = clampGeometry(saved.geometry, _viewport,
            minWidth: size.minWidth, minHeight: size.minHeight);
        final id = saved.id.isEmpty ? generateId() : saved.id;
        windows.add(WindowData(
          id: id,
          toolId: toolId,
          title: tool.title,
          geometry: geometry,
          minWidth: size.minWidth,
          minHeight: size.minHeight,
          zIndex: saved.zIndex,
          isMinimized: saved.isMinimized,
          isMaximized: saved.isMaximized,
          restoreGeometry: saved.restoreGeometry,
        ));
        if (workspace.desktop.activeWindowId == saved.id) {
          restoredActive = true;
        }
      }
      activeWindowId = restoredActive ? workspace.desktop.activeWindowId : null;
    }
    ready = true;
    notifyListeners();
  }

  int _nextZIndex() {
    var highest = 9;
    for (final window in windows) {
      highest = math.max(highest, window.zIndex);
    }
    return highest + 1;
  }

  void openFloatingWindow(String toolId) {
    final windowToolId = migrateWindowToolId(toolId);
    final tool = windowToolId == null ? null : getTool(windowToolId);
    final size = tool?.defaultSize;
    if (windowToolId == null || tool == null || size == null) return;

    for (final window in windows) {
      if (window.toolId == windowToolId) {
        focusWindow(window.id);
        return;
      }
    }

    final offset = (windows.length % 8) * 28.0;
    final geometry = clampGeometry(
      WindowGeometry(
          x: 110 + offset, y: 60 + offset, width: size.width, height: size.height),
      _viewport,
      minWidth: size.minWidth,
      minHeight: size.minHeight,
    );
    final id = generateId();
    windows.add(WindowData(
      id: id,
      toolId: windowToolId,
      title: tool.title,
      geometry: geometry,
      minWidth: size.minWidth,
      minHeight: size.minHeight,
      zIndex: _nextZIndex(),
    ));
    focusWindow(id);
  }

  WindowData? _findWindow(String id) {
    for (final window in windows) {
      if (window.id == id) return window;
    }
    return null;
  }

  void closeWindow(String id) {
    windows.removeWhere((window) => window.id == id);
    if (activeWindowId == id) activeWindowId = null;
    schedulePersist();
    notifyListeners();
  }

  void focusWindow(String id) {
    final window = _findWindow(id);
    if (window == null) return;
    window.isMinimized = false;
    window.zIndex = _nextZIndex();
    activeWindowId = id;
    schedulePersist();
    notifyListeners();
  }

  void minimizeWindow(String id) {
    final window = _findWindow(id);
    if (window == null) return;
    window.isMinimized = true;
    if (activeWindowId == id) activeWindowId = null;
    schedulePersist();
    notifyListeners();
  }

  void updateWindowGeometry(String id, WindowGeometry geometry) {
    final window = _findWindow(id);
    if (window == null || window.isMaximized) return;
    window.geometry = clampGeometry(geometry, _viewport,
        minWidth: window.minWidth, minHeight: window.minHeight);
    schedulePersist();
    notifyListeners();
  }

  void toggleWindowMaximize(String id) {
    final window = _findWindow(id);
    if (window == null) return;
    if (window.isMaximized && window.restoreGeometry != null) {
      window.geometry = clampGeometry(window.restoreGeometry!, _viewport,
          minWidth: window.minWidth, minHeight: window.minHeight);
      window.restoreGeometry = null;
      window.isMaximized = false;
    } else {
      window.restoreGeometry = window.geometry;
      window.geometry = WindowGeometry(
          x: 0, y: 0, width: _viewport.width, height: _viewport.height);
      window.isMaximized = true;
    }
    focusWindow(id);
  }

  void setActiveNavIndex(int index) {
    activeNavIndex = index.clamp(0, navItems.length - 1).toInt();
    schedulePersist();
    notifyListeners();
  }

  void toggleSidebar() {
    sidebarCollapsed = !sidebarCollapsed;
    schedulePersist();
    notifyListeners();
  }

  void addTodo(String text) {
    final value = text.trim();
    if (value.isEmpty || todos.length >= 500) return;
    todos.add(TodoItem(id: generateId(), text: value, done: false));
    schedulePersist();
    notifyListeners();
  }

  void toggleTodo(String id) {
    for (final todo in todos) {
      if (todo.id == id) {
        todo.done = !todo.done;
        break;
      }
    }
    schedulePersist();
    notifyListeners();
  }

  void deleteTodo(String id) {
    todos.removeWhere((todo) => todo.id == id);
    schedulePersist();
    notifyListeners();
  }

  void setAppearance({String? bgImageUrl, double? bgBlur}) {
    if (bgImageUrl != null) this.bgImageUrl = bgImageUrl;
    if (bgBlur != null) this.bgBlur = bgBlur.clamp(0, 100).toDouble();
    schedulePersist();
    notifyListeners();
  }

  void toggleTheme() {
    theme = theme == 'dark' ? 'light' : 'dark';
    schedulePersist();
    notifyListeners();
  }

  void markTimersChanged() {
    schedulePersist();
    notifyListeners();
  }

  void recordToolUsage(String id) {
    RecentToolUsage? existing;
    for (final item in recentTools) {
      if (item.id == id) {
        existing = item;
        break;
      }
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    if (existing != null) {
      existing.lastUsedAt = now;
      existing.useCount += 1;
    } else {
      recentTools.add(RecentToolUsage(id: id, lastUsedAt: now, useCount: 1));
    }
    recentTools.sort((a, b) => b.lastUsedAt.compareTo(a.lastUsedAt));
    if (recentTools.length > 30) {
      recentTools.removeRange(30, recentTools.length);
    }
    schedulePersist();
  }

  void toggleFavorite(String id) {
    if (favorites.contains(id)) {
      favorites.remove(id);
    } else {
      favorites.add(id);
      if (favorites.length > 20) favorites.removeAt(0);
    }
    schedulePersist();
    notifyListeners();
  }

  WorkspaceTemplate saveWorkspaceTemplate(String name) {
    final normalized = name.trim();
    if (normalized.isEmpty || normalized.length > 40) {
      throw ArgumentError('模板名称长度必须为 1 到 40 个字符');
    }
    if (workspaceTemplates.any(
        (item) => item.name.toLowerCase() == normalized.toLowerCase())) {
      throw ArgumentError('已经存在同名工作区模板');
    }
    if (workspaceTemplates.length >= 20) {
      throw ArgumentError('最多保存 20 个工作区模板');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final template = WorkspaceTemplate(
      id: generateId(),
      name: normalized,
      createdAt: now,
      updatedAt: now,
      preferences: _preferencesSnapshot(),
      desktop: _desktopSnapshot(),
      timers: timerPreset(timers),
    );
    workspaceTemplates.insert(0, template);
    schedulePersist();
    notifyListeners();
    return template;
  }

  void deleteWorkspaceTemplate(String id) {
    workspaceTemplates.removeWhere((item) => item.id == id);
    schedulePersist();
    notifyListeners();
  }

  void applyWorkspaceTemplate(String id) {
    WorkspaceTemplate? template;
    for (final item in workspaceTemplates) {
      if (item.id == id) {
        template = item;
        break;
      }
    }
    if (template == null) throw ArgumentError('找不到工作区模板');

    final idMap = <String, String>{};
    final restored = <WindowData>[];
    for (final saved in template.desktop.windows) {
      final toolId = migrateWindowToolId(saved.toolId);
      final tool = toolId == null ? null : getTool(toolId);
      final size = tool?.defaultSize;
      if (toolId == null || tool == null || size == null) continue;
      final newId = generateId();
      idMap[saved.id] = newId;
      restored.add(WindowData(
        id: newId,
        toolId: toolId,
        title: tool.title,
        geometry: clampGeometry(saved.geometry, _viewport,
            minWidth: size.minWidth, minHeight: size.minHeight),
        minWidth: size.minWidth,
        minHeight: size.minHeight,
        zIndex: saved.zIndex,
        isMinimized: saved.isMinimized,
        isMaximized: saved.isMaximized,
        restoreGeometry: saved.restoreGeometry,
      ));
    }

    theme = template.preferences.theme;
    bgImageUrl = template.preferences.bgImageUrl.isEmpty
        ? defaultWallpaper
        : template.preferences.bgImageUrl;
    bgBlur = template.preferences.bgBlur.clamp(0, 100).toDouble();
    sidebarCollapsed = template.preferences.sidebarCollapsed;
    activeNavIndex = template.desktop.activeNavIndex.clamp(0, 2).toInt();
    windows
      ..clear()
      ..addAll(restored);
    activeWindowId = template.desktop.activeWindowId == null
        ? null
        : idMap[template.desktop.activeWindowId];
    timers = reconcileTimers(timerPreset(template.timers));
    schedulePersist();
    notifyListeners();
  }

  void addActivity({
    required String source,
    required String title,
    required String value,
    ToolAccent accent = ToolAccent.teal,
  }) {
    recentActivity.insert(
      0,
      ActivityEntry(
        source: source,
        title: title,
        value: value,
        meta: formatMeta(),
        accent: accent,
      ),
    );
    if (recentActivity.length > 4) {
      recentActivity.removeRange(4, recentActivity.length);
    }
    notifyListeners();
  }

  void schedulePersist() {
    if (!ready) return;
    _persistTimer?.cancel();
    _persistTimer = Timer(persistDelay, () {
      _persistTimer = null;
      persist();
    });
  }

  Future<void> persist() {
    if (!ready) return _persistQueue;
    _persistTimer?.cancel();
    _persistTimer = null;
    final snapshot = _snapshot();
    _persistQueue = _persistQueue
        .catchError((_) {})
        .then((_) => saveWorkspace(snapshot))
        .catchError((Object error) {
      debugPrint('Failed to persist workspace: $error');
    });
    return _persistQueue;
  }

  WorkspacePreferences _preferencesSnapshot() => WorkspacePreferences(
        theme: theme,
        bgImageUrl: bgImageUrl,
        bgBlur: bgBlur,
        sidebarCollapsed: sidebarCollapsed,
      );

  WorkspaceDesktop _desktopSnapshot() => WorkspaceDesktop(
        activeNavIndex: activeNavIndex,
        activeWindowId: activeWindowId,
        windows: windows
            .map((window) => PersistedWindow(
                  id: window.id,
                  toolId: window.toolId,
                  geometry: window.geometry,
                  zIndex: window.zIndex,
                  isMinimized: window.isMinimized,
                  isMaximized: window.isMaximized,
                  restoreGeometry: window.restoreGeometry,
                ))
            .toList(),
      );

  PersistedWorkspace _snapshot() => PersistedWorkspace(
        savedAt: DateTime.now().millisecondsSinceEpoch,
        preferences: _preferencesSnapshot(),
        desktop: _desktopSnapshot(),
        todos: todos
            .map((todo) =>
                TodoItem(id: todo.id, text: todo.text, done: todo.done))
            .toList(),
        timers: timers.copy(),
        workspaceTemplates: workspaceTemplates.toList(),
        launcher: LauncherPreferences(
          favorites: favorites.toList(),
          recentTools: recentTools
              .map((item) => RecentToolUsage(
                  id: item.id,
                  lastUsedAt: item.lastUsedAt,
                  useCount: item.useCount))
              .toList(),
          globalShortcut: globalShortcut,
        ),
      );

  @override
  void dispose() {
    _persistTimer?.cancel();
    super.dispose();
  }
}
