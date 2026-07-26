import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/tool_registry.dart';
import '../tools/actions.dart';

/// Launchpad listing every tool (ToolsPage counterpart of the original
/// "全部工具" view) plus the clipboard quick actions.
class ToolsPage extends StatelessWidget {
  const ToolsPage({super.key, required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actions =
        toolRegistry.where((tool) => tool.kind == ToolKind.action).toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('工具窗口', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final tool in launchpadTools)
                SizedBox(
                  width: 250,
                  child: _ToolCard(appState: appState, tool: tool),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Text('剪贴板快捷动作', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tool in actions)
                ActionChip(
                  avatar: Icon(tool.icon,
                      size: 16, color: accentColor(tool.accent)),
                  label: Text(tool.title),
                  tooltip: tool.description,
                  onPressed: () => runTool(appState, tool.id),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({required this.appState, required this.tool});

  final AppState appState;
  final ToolDefinition tool;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = accentColor(tool.accent);
    final isFavorite = appState.favorites.contains(tool.id);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => runTool(appState, tool.id),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: accent.withOpacity(0.16),
                    child: Icon(tool.icon, size: 18, color: accent),
                  ),
                  const Spacer(),
                  if (!tool.ported)
                    Tooltip(
                      message: '待接入本地实现',
                      child: Icon(Icons.construction,
                          size: 14, color: theme.hintColor),
                    ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    tooltip: isFavorite ? '取消收藏' : '收藏',
                    icon: Icon(
                      isFavorite ? Icons.star : Icons.star_border,
                      color: isFavorite ? Colors.amber : theme.hintColor,
                    ),
                    onPressed: () => appState.toggleFavorite(tool.id),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(tool.title, style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                tool.description,
                style: theme.textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (tool.shortcut != null) ...[
                const SizedBox(height: 8),
                Text(tool.shortcut!, style: theme.textTheme.labelSmall),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
