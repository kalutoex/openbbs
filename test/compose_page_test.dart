import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openbbs/pages/compose_page.dart';

Future<void> _pumpPage(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    const MaterialApp(
      home: ComposePage(forumName: 'test', forumTitle: '这是一个名字比较长的测试吧'),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('发帖页：能画、能输入、没配服务器时不发出去', (tester) async {
    await _pumpPage(tester, const Size(390, 844));

    expect(find.text('发新帖'), findsOneWidget);
    expect(find.text('标题'), findsOneWidget);
    expect(find.textContaining('说点什么…'), findsOneWidget);

    // 空着的时候发布按钮是灰的
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '发布'))
          .onPressed,
      isNull,
    );

    await tester.enterText(find.byType(TextField).first, '标题');
    await tester.enterText(find.byType(TextField).last, '正文一段');
    await tester.pump();

    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '发布'))
          .onPressed,
      isNotNull,
    );

    // 没设置服务器地址，应该弹提示而不是崩
    await tester.tap(find.widgetWithText(FilledButton, '发布'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('还没设置服务器地址'), findsOneWidget);

    // 让草稿防抖 timer 走完，别留下待处理的 timer
    await tester.pump(const Duration(seconds: 1));
  });

  // 小屏 + 键盘弹出时最容易挤爆
  for (final size in const [Size(320, 568), Size(360, 640), Size(412, 915)]) {
    testWidgets('小屏不溢出：${size.width.toInt()}x${size.height.toInt()}', (
      tester,
    ) async {
      await _pumpPage(tester, size);
      await tester.enterText(find.byType(TextField).first, '标题');
      await tester.enterText(find.byType(TextField).last, '这一段正文要够长，' * 12);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.widgetWithText(FilledButton, '发布'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
    });
  }
}
