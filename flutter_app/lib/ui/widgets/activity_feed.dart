import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/tool_registry.dart';

/// Recent activity feed (ActivityFeed.svelte) — last four operations.
class ActivityFeed extends StatelessWidget {
  const ActivityFeed({super.key, required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.history,
                    size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('最近操作', style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 8),
            for (final entry in appState.recentActivity)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 5),
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accentColor(entry.accent),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(entry.title,
                                    style: theme.textTheme.labelLarge,
                                    overflow: TextOverflow.ellipsis),
                              ),
                              Text(entry.meta,
                                  style: theme.textTheme.labelSmall),
                            ],
                          ),
                          Text(entry.value,
                              style: theme.textTheme.bodySmall,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
