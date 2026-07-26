import 'package:flutter/material.dart';

import '../core/app_state.dart';

Future<void> showSettingsDialog(BuildContext context, AppState appState) {
  return showDialog<void>(
    context: context,
    builder: (context) => SettingsDialog(appState: appState),
  );
}

/// Trimmed port of SettingsModal.svelte: appearance (wallpaper URL + blur)
/// and workspace template management.
class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key, required this.appState});

  final AppState appState;

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late final TextEditingController _wallpaperController =
      TextEditingController(text: widget.appState.bgImageUrl);
  final TextEditingController _templateNameController =
      TextEditingController();
  String? _templateError;

  @override
  void dispose() {
    _wallpaperController.dispose();
    _templateNameController.dispose();
    super.dispose();
  }

  void _saveTemplate() {
    try {
      widget.appState.saveWorkspaceTemplate(_templateNameController.text);
      setState(() {
        _templateError = null;
        _templateNameController.clear();
      });
    } on ArgumentError catch (error) {
      setState(() => _templateError = error.message?.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appState = widget.appState;
    return AlertDialog(
      title: const Text('设置'),
      content: SizedBox(
        width: 480,
        child: AnimatedBuilder(
          animation: appState,
          builder: (context, _) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('外观', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('深色主题'),
                  value: appState.theme == 'dark',
                  onChanged: (_) => appState.toggleTheme(),
                ),
                TextField(
                  controller: _wallpaperController,
                  decoration: const InputDecoration(
                    labelText: '壁纸 URL',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (value) =>
                      appState.setAppearance(bgImageUrl: value.trim()),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('壁纸模糊'),
                    Expanded(
                      child: Slider(
                        value: appState.bgBlur,
                        min: 0,
                        max: 100,
                        onChanged: (value) =>
                            appState.setAppearance(bgBlur: value),
                      ),
                    ),
                    Text('${appState.bgBlur.round()}'),
                  ],
                ),
                const Divider(height: 24),
                Text('工作区模板', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _templateNameController,
                        decoration: const InputDecoration(
                          hintText: '以当前布局创建模板…',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => _saveTemplate(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonal(
                      onPressed: _saveTemplate,
                      child: const Text('保存'),
                    ),
                  ],
                ),
                if (_templateError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _templateError!,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.error),
                    ),
                  ),
                const SizedBox(height: 8),
                if (appState.workspaceTemplates.isEmpty)
                  Text('尚未保存模板。保存后可在快速启动器中输入 "> workspace" 一键应用。',
                      style: theme.textTheme.bodySmall)
                else
                  for (final template in appState.workspaceTemplates)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.space_dashboard, size: 18),
                      title: Text(template.name),
                      subtitle: Text(
                          '${template.desktop.windows.length} 个工具窗口'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            child: const Text('应用'),
                            onPressed: () {
                              appState.applyWorkspaceTemplate(template.id);
                              Navigator.of(context).pop();
                            },
                          ),
                          IconButton(
                            iconSize: 16,
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => appState
                                .deleteWorkspaceTemplate(template.id),
                          ),
                        ],
                      ),
                    ),
                const Divider(height: 24),
                Text('关于', style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  'Congmiao Toolbox Flutter ${AppState.appVersion}\n'
                  'Flutter 分支移植自 Tauri 2 + Svelte 5 主分支。',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            widget.appState
                .setAppearance(bgImageUrl: _wallpaperController.text.trim());
            Navigator.of(context).pop();
          },
          child: const Text('完成'),
        ),
      ],
    );
  }
}
