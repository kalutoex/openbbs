import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openbbs/widgets/live_time.dart';

void main() {
  testWidgets('照常显示相对时间', (tester) async {
    final at =
        DateTime.now()
            .subtract(const Duration(minutes: 5))
            .millisecondsSinceEpoch ~/
        1000;

    await tester.pumpWidget(
      Directionality(textDirection: TextDirection.ltr, child: LiveTime(at)),
    );
    expect(find.text('5 分钟前'), findsOneWidget);
  });

  testWidgets('节拍一响，挂着的文字自己重算', (tester) async {
    var n = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: LiveTimeText(() => '第${++n}次'),
      ),
    );
    expect(find.text('第1次'), findsOneWidget);

    // 不重建页面，只敲一下节拍：说明列表放着不动，时间也会走。
    beatClock();
    await tester.pump();
    expect(find.text('第2次'), findsOneWidget);
  });
}
