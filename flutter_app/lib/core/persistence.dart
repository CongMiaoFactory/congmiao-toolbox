import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'workspace.dart';

/// Stores the workspace snapshot as a single JSON document, mirroring the
/// Tauri build's `workspace.json` (schema v1). A corrupt document is backed
/// up under a timestamped key instead of being silently dropped, matching
/// the `recover_workspace_store` behavior of the Rust backend.
const _workspaceKey = 'congmiao.workspace.v1';

Future<PersistedWorkspace?> loadWorkspace() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_workspaceKey);
  if (raw == null || raw.isEmpty) return null;
  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    decoded = null;
  }
  if (!isWorkspaceV1(decoded)) {
    final backupKey =
        'congmiao.workspace.corrupt.${DateTime.now().millisecondsSinceEpoch}';
    await prefs.setString(backupKey, raw);
    await prefs.remove(_workspaceKey);
    return null;
  }
  return PersistedWorkspace.fromJson(decoded as Map<String, dynamic>);
}

Future<void> saveWorkspace(PersistedWorkspace workspace) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_workspaceKey, jsonEncode(workspace.toJson()));
}
