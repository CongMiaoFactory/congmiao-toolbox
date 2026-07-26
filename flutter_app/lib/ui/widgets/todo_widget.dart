import 'package:flutter/material.dart';

import '../../core/app_state.dart';

/// Desktop todo list widget (TodoWidget.svelte).
class TodoWidget extends StatefulWidget {
  const TodoWidget({super.key, required this.appState});

  final AppState appState;

  @override
  State<TodoWidget> createState() => _TodoWidgetState();
}

class _TodoWidgetState extends State<TodoWidget> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    widget.appState.addTodo(_controller.text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final todos = widget.appState.todos;
    final remaining = todos.where((todo) => !todo.done).length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.checklist,
                    size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('待办', style: theme.textTheme.titleSmall),
                const Spacer(),
                Text('$remaining 项未完成', style: theme.textTheme.labelSmall),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: '添加待办后回车',
                isDense: true,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.add, size: 18),
                  onPressed: _submit,
                ),
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: todos.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text('暂无待办',
                          style: theme.textTheme.bodySmall),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: todos.length,
                      itemBuilder: (context, index) {
                        final todo = todos[index];
                        return Row(
                          children: [
                            Checkbox(
                              value: todo.done,
                              visualDensity: VisualDensity.compact,
                              onChanged: (_) =>
                                  widget.appState.toggleTodo(todo.id),
                            ),
                            Expanded(
                              child: Text(
                                todo.text,
                                overflow: TextOverflow.ellipsis,
                                style: todo.done
                                    ? theme.textTheme.bodyMedium?.copyWith(
                                        decoration:
                                            TextDecoration.lineThrough,
                                        color: theme.hintColor,
                                      )
                                    : theme.textTheme.bodyMedium,
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              iconSize: 16,
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () =>
                                  widget.appState.deleteTodo(todo.id),
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
