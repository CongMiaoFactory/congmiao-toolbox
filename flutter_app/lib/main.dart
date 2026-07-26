import 'package:flutter/material.dart';

import 'core/app_state.dart';
import 'ui/home_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final appState = AppState();
  runApp(CongmiaoApp(appState: appState));
}

class CongmiaoApp extends StatefulWidget {
  const CongmiaoApp({super.key, required this.appState});

  final AppState appState;

  @override
  State<CongmiaoApp> createState() => _CongmiaoAppState();
}

class _CongmiaoAppState extends State<CongmiaoApp> {
  @override
  void initState() {
    super.initState();
    widget.appState.hydrate();
  }

  ThemeData _buildTheme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2DD4BF),
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          brightness == Brightness.dark ? const Color(0xFF0F1115) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.appState,
      builder: (context, _) {
        return MaterialApp(
          title: 'Congmiao Toolbox',
          debugShowCheckedModeBanner: false,
          theme: _buildTheme(Brightness.light),
          darkTheme: _buildTheme(Brightness.dark),
          themeMode: widget.appState.theme == 'dark'
              ? ThemeMode.dark
              : ThemeMode.light,
          home: HomeShell(appState: widget.appState),
        );
      },
    );
  }
}
