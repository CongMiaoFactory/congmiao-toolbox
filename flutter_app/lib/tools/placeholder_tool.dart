import 'package:flutter/material.dart';

import '../core/tool_registry.dart';

/// Placeholder window body for tools whose original implementation depends
/// on the Rust backend and has not been ported yet.
class PlaceholderTool extends StatelessWidget {
  const PlaceholderTool({super.key, required this.toolId, required this.note});

  final String toolId;
  final String note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tool = getTool(toolId);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                tool?.icon ?? Icons.construction,
                size: 48,
                color: tool == null
                    ? theme.hintColor
                    : accentColor(tool.accent),
              ),
              const SizedBox(height: 16),
              Text(tool?.title ?? toolId, style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                tool?.description ?? '',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Card(
                color: theme.colorScheme.surfaceContainerHighest
                    .withOpacity(0.5),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline,
                          size: 16, color: theme.hintColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          note,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
