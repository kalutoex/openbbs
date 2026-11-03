import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shijianxian_app/main.dart';
import 'package:shijianxian_app/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('首帧能画出来：设置读盘 + MaterialApp 构建都不抛', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(() => AppState.instance.loadPrefs());
    await tester.pumpWidget(const ShijianxianApp());
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(Scaffold), findsWidgets);
  });

  testWidgets('带着上次存的深色 + 非默认色相启动也不抛', (tester) async {
    SharedPreferences.setMockInitialValues({
      'theme_mode': ThemeMode.dark.index,
      'accent_hue': 300.0,
      'font_scale': 1.15,
    });
    await tester.runAsync(() => AppState.instance.loadPrefs());
    expect(AppState.instance.themeMode.value, ThemeMode.dark);
    await tester.pumpWidget(const ShijianxianApp());
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
