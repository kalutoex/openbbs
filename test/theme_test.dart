import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openbbs/pages/theme_color_page.dart';
import 'package:openbbs/store.dart';
import 'package:openbbs/theme.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AppState.instance.accentHue.value = AppState.defaultHue;
  });

  testWidgets('拖色带改的是主题色，松手落盘', (tester) async {
    await tester.pumpWidget(
      AnimatedBuilder(
        animation: AppState.instance.accentHue,
        builder: (_, _) {
          final c = AppState.instance.accentColor;
          return MaterialApp(
            theme: buildAppTheme(Brightness.light, c),
            home: const ThemeColorPage(),
          );
        },
      ),
    );

    expect(AppState.instance.accentHue.value, AppState.defaultHue);
    expect(find.text('青绿'), findsOneWidget);

    final slider = find.byType(Slider);
    expect(slider, findsOneWidget);
    // 从色带中间往右拖，色相应当变大。
    await tester.drag(slider, const Offset(120, 0));
    await tester.pumpAndSettle();

    final hue = AppState.instance.accentHue.value;
    expect(hue, greaterThan(AppState.defaultHue));
    // 拖动后主色确实跟着换了。
    expect(
      AppState.instance.accentColor,
      isNot(const Color(0xFF1F9C8F)),
    );

    // 松手后已写入 SharedPreferences。
    final p = await SharedPreferences.getInstance();
    expect(p.getDouble('accent_hue'), hue);
  });

  test('色相夹在 0-350，异常值回落默认', () {
    expect(AppState.normalizeHue(-10), 0);
    expect(AppState.normalizeHue(400), 350);
    expect(AppState.normalizeHue(double.nan), AppState.defaultHue);
    expect(AppState.hueName(AppState.defaultHue), '青绿');
  });

  test('重启后读回上次的色相', () async {
    SharedPreferences.setMockInitialValues({'accent_hue': 300.0});
    await AppState.instance.init();
    expect(AppState.instance.accentHue.value, 300.0);
  });
}
