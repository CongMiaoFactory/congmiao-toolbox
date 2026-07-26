import 'package:congmiao_toolbox_flutter/core/app_state.dart';
import 'package:congmiao_toolbox_flutter/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Smoke test: the app hydrates an empty workspace and boots into the
/// desktop shell (topbar, navigation, dashboard widgets).
void main() {
  testWidgets('boots into the desktop shell', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final appState = AppState();

    await tester.pumpWidget(CongmiaoApp(appState: appState));
    // Let the async hydrate finish and the shell replace the loading view.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Congmiao Toolbox'), findsOneWidget);
    expect(find.text('仪表盘'), findsWidgets);
    expect(find.text('待办'), findsOneWidget);
    expect(find.text('番茄钟'), findsOneWidget);

    // Unmount so periodic widget timers are disposed, then flush the
    // debounced persistence timer scheduled by the viewport reconcile.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 400));
  });
}
