import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openbbs/main.dart';
import 'package:openbbs/pages/feed_tab.dart';
import 'package:openbbs/store.dart';

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

  testWidgets('窗口从窄拖到宽，时间线页的 State 不重建', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(() => AppState.instance.loadPrefs());
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1200);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const ShijianxianApp());
    await tester.pump();
    final before = tester.element(find.byType(FeedTab, skipOffstage: false));

    // 跨过 840 的那一下：底栏收进左侧 NavigationRail。
    // 以前 body 是 `wide ? Row(rail, content) : content`，父链一变整页重建，
    // 滚动位置和没发出去的草稿都跟着没。
    tester.view.physicalSize = const Size(1200, 800);
    await tester.pump();
    final after = tester.element(find.byType(FeedTab, skipOffstage: false));

    expect(identical(before, after), isTrue);
    expect(find.byType(NavigationRail), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
