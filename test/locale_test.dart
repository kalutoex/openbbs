import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// 长按文字弹出来的那排按钮，必须跟着系统走中文。
Widget _app({required bool withZh}) {
  return MaterialApp(
    locale: withZh ? const Locale('zh', 'CN') : null,
    supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
    localizationsDelegates: withZh
        ? const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ]
        : null,
    home: const Scaffold(
      body: Padding(
        padding: EdgeInsets.all(16),
        child: TextField(
          controller: null,
          decoration: InputDecoration(hintText: '正文'),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('配了中文本地化：长按出「全选」「复制」', (tester) async {
    await tester.pumpWidget(_app(withZh: true));
    await tester.enterText(find.byType(TextField), '一段可以复制的文字');
    await tester.pump();

    await tester.longPress(find.byType(TextField));
    await tester.pumpAndSettle();

    // 长按先给「全选」，再点一下全选中，就该出「复制」
    expect(find.text('全选'), findsWidgets);
    expect(find.text('Select all'), findsNothing);
    expect(find.text('Copy'), findsNothing);

    await tester.tap(find.text('全选').last);
    await tester.pumpAndSettle();
    expect(find.text('复制'), findsWidgets);
    expect(find.text('Copy'), findsNothing);
  });
}
