import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shijianxian_app/pages/forums_tab.dart';

Future<void> _pump(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    MaterialApp(
      home: ForumsTab(onMenu: () {}),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('板块页：标题、搜索框在，没服务器时不崩', (tester) async {
    await _pump(tester, const Size(390, 844));

    expect(find.text('板块'), findsOneWidget);
    expect(find.text('搜團'), findsOneWidget);
    expect(find.text('刷新'), findsNothing); // tooltip 不算可见文本

    // 没网/没服务器应该给提示或骨架，不该抛异常
    expect(tester.takeException(), isNull);
  });

  for (final size in const [Size(320, 568), Size(360, 640), Size(412, 915)]) {
    testWidgets('板块页小屏不溢出：${size.width.toInt()}x${size.height.toInt()}', (
      tester,
    ) async {
      await _pump(tester, size);
      await tester.enterText(find.byType(TextField), '测试');
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
    });
  }
}
