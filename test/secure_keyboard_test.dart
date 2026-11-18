// OPPO / realme UI 碰到「密码类型」的输入框会把键盘换成系统安全键盘，
// 那种键盘没有候选词、中文难打。Flutter 在 obscureText: true 且没给
// keyboardType 时把输入框标成 TYPE_TEXT_VARIATION_PASSWORD，就会触发。
// 所以带 obscureText 的框必须显式声明 visiblePassword，系统按普通文本框处理。
//
// 这层用源码扫一遍兜住：以后新加密码框忘了写 keyboardType，测试就红。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('带 obscureText 的输入框都声明了 visiblePassword', () {
    final dir = Directory('lib');
    expect(dir.existsSync(), isTrue);

    final bad = <String>[];
    for (final f in dir.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (!lines[i].contains('obscureText:')) continue;
        final from = (i - 12).clamp(0, i);
        final to = (i + 12).clamp(i, lines.length - 1);
        final around = lines.sublist(from, to + 1).join('\n');
        if (!around.contains('TextInputType.visiblePassword')) {
          bad.add('${f.path}:${i + 1}');
        }
      }
    }

    expect(bad, isEmpty, reason: '这些密码框会弹 OPPO/realme 安全键盘：$bad');
  });
}
