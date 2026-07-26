import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import '../core/tool_registry.dart';
import '../core/workspace.dart' as workspace;
import '../tools/actions.dart';
import '../tools/placeholder_tool.dart';
import '../tools/tool_windows.dart';
import 'command_palette.dart';
import 'dashboard_page.dart';
import 'floating_window.dart';
import 'screen_time_page.dart';
import 'settings_dialog.dart';
import 'tools_page.dart';

/// Root layout: wallpaper, topbar, navigation rail, the active page, the
/// floating tool-window layer and the dock — the Flutter counterpart of
/// `App.svelte`'s desktop mode.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.appState});

  final AppState appState;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  bool _paletteOpen = false;

  AppState get appState => widget.appState;

  Future<void> _openPalette() async {
    if (_paletteOpen) return;
    _paletteOpen = true;
    try {
      await showCommandPalette(context, appState);
    } finally {
      _paletteOpen = false;
    }
  }

  Map<ShortcutActivator, VoidCallback> get _shortcuts => {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            _openPalette,
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
            _openPalette,
        const SingleActivator(LogicalKeyboardKey.keyT, control: true): () =>
            runTool(appState, 'timer'),
        const SingleActivator(LogicalKeyboardKey.keyJ, control: true): () =>
            runTool(appState, 'json'),
        const SingleActivator(LogicalKeyboardKey.keyL, control: true): () =>
            runTool(appState, 'lucky-wheel'),
        const SingleActivator(LogicalKeyboardKey.keyU, control: true): () =>
            runTool(appState, 'url-encode'),
        const SingleActivator(LogicalKeyboardKey.keyB, control: true): () =>
            runTool(appState, 'base64'),
        const SingleActivator(LogicalKeyboardKey.keyH, control: true): () =>
            runTool(appState, 'hash-check'),
      };

  Widget _buildWallpaper() {
    final image = Image.network(
      appState.bgImageUrl,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF16202A), Color(0xFF0F1115)],
          ),
        ),
      ),
    );
    if (appState.bgBlur <= 0) return Positioned.fill(child: image);
    return Positioned.fill(
      child: ImageFiltered(
        imageFilter: ui.ImageFilter.blur(
          sigmaX: appState.bgBlur / 6,
          sigmaY: appState.bgBlur / 6,
        ),
        child: image,
      ),
    );
  }

  Widget _buildTopbar(BuildContext context) {
    final theme = Theme.of(context);
    final nav = navItems[appState.activeNavIndex];
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: theme.colorScheme.surface.withValues(alpha: 0.72),
      child: Row(
        children: [
          IconButton(
            tooltip: '展开 / 收起侧栏',
            icon: const Icon(Icons.menu),
            onPressed: appState.toggleSidebar,
          ),
          const SizedBox(width: 4),
          Text('Congmiao Toolbox', style: theme.textTheme.titleMedium),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              nav.caption,
              style: theme.textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Spacer(),
          OutlinedButton.icon(
            icon: const Icon(Icons.search, size: 16),
            label: const Text('快速搜索  Ctrl+K'),
            onPressed: _openPalette,
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: '切换主题',
            icon: Icon(appState.theme == 'dark'
                ? Icons.light_mode
                : Icons.dark_mode),
            onPressed: appState.toggleTheme,
          ),
          IconButton(
            tooltip: '设置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => showSettingsDialog(context, appState),
          ),
        ],
      ),
    );
  }

  Widget _buildPage() {
    switch (appState.activeNavIndex) {
      case 1:
        return ToolsPage(appState: appState);
      case 2:
        return const ScreenTimePage();
      default:
        return DashboardPage(appState: appState);
    }
  }

  Widget _buildDesktop(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          appState.setViewport(workspace.Viewport(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
          ));
        });

        final visibleWindows =
            appState.windows.where((window) => !window.isMinimized).toList()
              ..sort((a, b) => a.zIndex.compareTo(b.zIndex));

        return Stack(
          children: [
            Positioned.fill(child: _buildPage()),
            for (final window in visibleWindows)
              FloatingWindowFrame(
                key: ValueKey(window.id),
                appState: appState,
                window: window,
                isActive: appState.activeWindowId == window.id,
                child: windowToolBuilders[window.toolId]
                        ?.call(appState) ??
                    PlaceholderTool(
                        toolId: window.toolId, note: '未注册的工具窗口'),
              ),
          ],
        );
      },
    );
  }

  Widget _buildDock(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: theme.colorScheme.surface.withValues(alpha: 0.72),
      child: Row(
        children: [
          Expanded(
            child: appState.windows.isEmpty
                ? Text('打开的工具窗口会出现在这里 · Ctrl+K 打开快速搜索',
                    style: theme.textTheme.labelSmall)
                : ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final window in appState.windows)
                        Padding(
                          padding: const EdgeInsets.only(right: 8, top: 6),
                          child: ActionChip(
                            avatar: Icon(
                              getTool(window.toolId)?.icon ?? Icons.window,
                              size: 14,
                              color: appState.activeWindowId == window.id
                                  ? theme.colorScheme.primary
                                  : null,
                            ),
                            label: Text(window.title),
                            labelStyle: theme.textTheme.labelSmall,
                            visualDensity: VisualDensity.compact,
                            onPressed: () {
                              if (window.isMinimized ||
                                  appState.activeWindowId != window.id) {
                                appState.focusWindow(window.id);
                              } else {
                                appState.minimizeWindow(window.id);
                              }
                            },
                          ),
                        ),
                    ],
                  ),
          ),
          Text('v${AppState.appVersion}', style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appState,
      builder: (context, _) {
        if (!appState.ready) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('正在恢复工作区…'),
                ],
              ),
            ),
          );
        }

        return CallbackShortcuts(
          bindings: _shortcuts,
          child: Focus(
            autofocus: true,
            child: Scaffold(
              body: Stack(
                children: [
                  _buildWallpaper(),
                  Column(
                    children: [
                      _buildTopbar(context),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            NavigationRail(
                              extended: !appState.sidebarCollapsed,
                              minExtendedWidth: 180,
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .surface
                                  .withValues(alpha: 0.6),
                              selectedIndex: appState.activeNavIndex,
                              onDestinationSelected:
                                  appState.setActiveNavIndex,
                              labelType: appState.sidebarCollapsed
                                  ? NavigationRailLabelType.all
                                  : NavigationRailLabelType.none,
                              destinations: const [
                                NavigationRailDestination(
                                  icon: Icon(Icons.dashboard_outlined),
                                  selectedIcon: Icon(Icons.dashboard),
                                  label: Text('仪表盘'),
                                ),
                                NavigationRailDestination(
                                  icon: Icon(Icons.apps_outlined),
                                  selectedIcon: Icon(Icons.apps),
                                  label: Text('全部工具'),
                                ),
                                NavigationRailDestination(
                                  icon: Icon(Icons.schedule_outlined),
                                  selectedIcon: Icon(Icons.schedule),
                                  label: Text('使用时长'),
                                ),
                              ],
                            ),
                            Expanded(child: _buildDesktop(context)),
                          ],
                        ),
                      ),
                      _buildDock(context),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
