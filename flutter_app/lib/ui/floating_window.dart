import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/tool_registry.dart';
import '../core/workspace.dart';

/// In-app draggable/resizable tool window, the Flutter counterpart of
/// `FloatingWindow.svelte`. Geometry mutations flow through [AppState] so
/// they are clamped and persisted exactly like the original.
class FloatingWindowFrame extends StatelessWidget {
  const FloatingWindowFrame({
    super.key,
    required this.appState,
    required this.window,
    required this.isActive,
    required this.child,
  });

  final AppState appState;
  final WindowData window;
  final bool isActive;
  final Widget child;

  void _dragBy(Offset delta) {
    final geometry = window.geometry;
    appState.updateWindowGeometry(
      window.id,
      WindowGeometry(
        x: geometry.x + delta.dx,
        y: geometry.y + delta.dy,
        width: geometry.width,
        height: geometry.height,
      ),
    );
  }

  void _resizeBy(Offset delta) {
    final geometry = window.geometry;
    appState.updateWindowGeometry(
      window.id,
      WindowGeometry(
        x: geometry.x,
        y: geometry.y,
        width: geometry.width + delta.dx,
        height: geometry.height + delta.dy,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tool = getTool(window.toolId);
    final accent =
        tool == null ? theme.colorScheme.primary : accentColor(tool.accent);

    return Positioned(
      left: window.geometry.x,
      top: window.geometry.y,
      width: window.geometry.width,
      height: window.geometry.height,
      child: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onTapDown: (_) => appState.focusWindow(window.id),
        child: Material(
          elevation: isActive ? 18 : 8,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          color: theme.colorScheme.surface.withOpacity(0.97),
          child: Column(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanDown: (_) => appState.focusWindow(window.id),
                onPanUpdate: (details) => _dragBy(details.delta),
                onDoubleTap: () => appState.toggleWindowMaximize(window.id),
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withOpacity(isActive ? 0.9 : 0.6),
                    border: Border(
                      bottom: BorderSide(
                        color: isActive
                            ? accent.withOpacity(0.5)
                            : theme.dividerColor.withOpacity(0.4),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(tool?.icon ?? Icons.window, size: 18, color: accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          window.title,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        iconSize: 16,
                        tooltip: '最小化',
                        icon: const Icon(Icons.remove),
                        onPressed: () => appState.minimizeWindow(window.id),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        iconSize: 16,
                        tooltip: window.isMaximized ? '还原' : '最大化',
                        icon: Icon(window.isMaximized
                            ? Icons.filter_none
                            : Icons.crop_square),
                        onPressed: () =>
                            appState.toggleWindowMaximize(window.id),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        iconSize: 16,
                        tooltip: '关闭',
                        icon: const Icon(Icons.close),
                        onPressed: () => appState.closeWindow(window.id),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(child: child),
              SizedBox(
                height: 14,
                child: Row(
                  children: [
                    const Spacer(),
                    MouseRegion(
                      cursor: SystemMouseCursors.resizeDownRight,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanDown: (_) => appState.focusWindow(window.id),
                        onPanUpdate: (details) => _resizeBy(details.delta),
                        child: Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(
                            Icons.south_east,
                            size: 12,
                            color: theme.hintColor,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
