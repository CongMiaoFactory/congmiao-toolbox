import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import '../core/launcher.dart';
import '../core/tool_registry.dart';
import '../tools/actions.dart';

Future<void> showCommandPalette(BuildContext context, AppState appState) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black38,
    builder: (context) => CommandPaletteDialog(appState: appState),
  );
}

class CommandPaletteDialog extends StatefulWidget {
  const CommandPaletteDialog({super.key, required this.appState});

  final AppState appState;

  @override
  State<CommandPaletteDialog> createState() => _CommandPaletteDialogState();
}

class _CommandPaletteDialogState extends State<CommandPaletteDialog> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<LauncherResult> _results = const [];
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _refresh('');
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _refresh(String query) {
    setState(() {
      _results = buildLauncherResults(
        query,
        toolRegistry,
        widget.appState.workspaceTemplates,
        widget.appState.favorites,
        widget.appState.recentTools,
      );
      _selectedIndex = 0;
    });
  }

  void _moveSelection(int delta) {
    if (_results.isEmpty) return;
    setState(() {
      _selectedIndex =
          (_selectedIndex + delta).clamp(0, _results.length - 1).toInt();
    });
  }

  Future<void> _runSelected([int? index]) async {
    final target = index ?? _selectedIndex;
    if (target < 0 || target >= _results.length) return;
    final result = _results[target];
    Navigator.of(context).pop();
    await executeLauncherResult(widget.appState, result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      alignment: const Alignment(0, -0.6),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 480),
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                _moveSelection(1),
            const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                _moveSelection(-1),
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  onChanged: _refresh,
                  onSubmitted: (_) => _runSelected(),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: '搜索工具，或输入 > timer 10m / > todo … / 3*(4+5) / example.com',
                    border: InputBorder.none,
                  ),
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: _results.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text('没有匹配结果',
                            style: theme.textTheme.bodyMedium),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        shrinkWrap: true,
                        itemCount: _results.length,
                        itemBuilder: (context, index) {
                          final result = _results[index];
                          final selected = index == _selectedIndex;
                          final accent = accentColor(result.accent);
                          return ListTile(
                            dense: true,
                            selected: selected,
                            selectedTileColor:
                                theme.colorScheme.primaryContainer
                                    .withValues(alpha: 0.35),
                            leading: CircleAvatar(
                              radius: 14,
                              backgroundColor: accent.withValues(alpha: 0.18),
                              child:
                                  Icon(result.icon, size: 16, color: accent),
                            ),
                            title: Text(result.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            subtitle: Text(result.description,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            trailing: result.shortcut == null
                                ? null
                                : Text(result.shortcut!,
                                    style: theme.textTheme.labelSmall),
                            onTap: () => _runSelected(index),
                          );
                        },
                      ),
              ),
              const Divider(height: 1),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Text('↑↓ 选择 · Enter 执行 · Esc 关闭',
                        style: theme.textTheme.labelSmall),
                    const Spacer(),
                    Text('Congmiao Launcher',
                        style: theme.textTheme.labelSmall),
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
