import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openbbs/widgets/file_card.dart';

/// 私信气泡套着 IntrinsicWidth，卡片要是报不出固有宽度就会被压成 0，
/// 看着像文件没发出去，也点不中。这条守着别再退回 LayoutBuilder。
Future<void> _pumpCard(WidgetTester tester, {double maxWidth = 300}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: IntrinsicWidth(
              child: FileCards(
                files: [
                  PostFile(
                    url: '/f/0123456789abcdef0123',
                    name: 'a.zip',
                    size: 2048,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('文件卡片在 IntrinsicWidth 里仍有宽度、不报错', (tester) async {
    await _pumpCard(tester);

    expect(tester.takeException(), isNull);
    final size = tester.getSize(find.byType(FileCards));
    expect(size.width, greaterThan(50));
    // 不超过外面给的宽度上限
    expect(size.width, lessThanOrEqualTo(300));
  });

  testWidgets('宽屏下卡片停在 420，不铺满', (tester) async {
    await _pumpCard(tester, maxWidth: 800);

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(FileCards)).width, 420);
  });
}
