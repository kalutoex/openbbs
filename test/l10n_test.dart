import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openbbs/l10n/app_localizations.dart';
import 'package:openbbs/l10n/error_text.dart';
import 'package:openbbs/api.dart';

/// ARB 这条链路本身要能跑通：切语言，字符串跟着变；
/// 客户端自造的错误跟着翻译，服务端下发的原文不许被改写。
Widget _probe(Locale locale, void Function(BuildContext) onBuild) {
  return MaterialApp(
    locale: locale,
    supportedLocales: L.supportedLocales,
    localizationsDelegates: L.localizationsDelegates,
    home: Builder(
      builder: (c) {
        onBuild(c);
        return const SizedBox.shrink();
      },
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('中文环境取到中文，英文环境取到英文', (tester) async {
    late L zh;
    await tester.pumpWidget(_probe(const Locale('zh'), (c) => zh = L.of(c)));
    expect(zh.language, '语言');
    expect(zh.settings, '设置');

    late L en;
    await tester.pumpWidget(_probe(const Locale('en'), (c) => en = L.of(c)));
    expect(en.language, 'Language');
    expect(en.settings, 'Settings');
  });

  testWidgets('客户端自造的错误按语言翻译', (tester) async {
    String? zhText;
    await tester.pumpWidget(_probe(const Locale('zh'), (c) {
      zhText = errorText(c, ApiException('还没设置服务器地址', code: 'notConfigured'));
    }));
    expect(zhText, '还没设置服务器地址');

    String? enText;
    await tester.pumpWidget(_probe(const Locale('en'), (c) {
      enText = errorText(c, ApiException('还没设置服务器地址', code: 'notConfigured'));
    }));
    // 原文是中文，英文界面下必须换成英文，而不是原样漏出去
    expect(enText, 'Server address is not set yet');
  });

  testWidgets('服务端下发的错误原样显示，不翻译', (tester) async {
    String? enText;
    await tester.pumpWidget(_probe(const Locale('en'), (c) {
      enText = errorText(c, ApiException('帖子不存在'));
    }));
    expect(enText, '帖子不存在');
  });

  testWidgets('带占位符的错误把状态码填进去', (tester) async {
    String? enText;
    await tester.pumpWidget(_probe(const Locale('en'), (c) {
      enText = errorText(
        c,
        ApiException('请求失败（404）', code: 'requestFailed', status: 404),
      );
    }));
    expect(enText, 'Request failed (404)');
  });
}
