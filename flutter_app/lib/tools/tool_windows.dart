import 'package:flutter/material.dart';

import '../core/app_state.dart';
import 'batch_rename_tool.dart';
import 'color_tool.dart';
import 'duplicate_scanner_tool.dart';
import 'encoder_tool.dart';
import 'file_organizer_tool.dart';
import 'hash_tool.dart';
import 'image_converter_tool.dart';
import 'json_tool.dart';
import 'lucky_wheel_tool.dart';
import 'peek_pc_tool.dart';
import 'python_tool.dart';
import 'timer_tool.dart';
import 'translator_tool.dart';

/// Mirror of `src/windowComponents.ts`: one body builder per window tool.
final Map<String, Widget Function(AppState appState)> windowToolBuilders = {
  'json': (appState) => JsonTool(appState: appState),
  'python': (appState) => PythonTool(appState: appState),
  'encoder': (appState) => EncoderTool(appState: appState),
  'color': (appState) => ColorTool(appState: appState),
  'hash': (appState) => HashTool(appState: appState),
  'image': (appState) => ImageConverterTool(appState: appState),
  'timer': (appState) => TimerTool(appState: appState),
  'translator': (appState) => TranslatorTool(appState: appState),
  'peek_pc': (appState) => PeekPCTool(appState: appState),
  'lucky-wheel': (appState) => LuckyWheelTool(appState: appState),
  'batch-rename': (appState) => BatchRenameTool(appState: appState),
  'sort-rule': (appState) => FileOrganizerTool(appState: appState),
  'duplicate-scan': (appState) => DuplicateScannerTool(appState: appState),
};
