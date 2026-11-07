import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openbbs/ui_config.dart';
import 'package:openbbs/widgets/file_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 界面参数是后台下发的，脏数据、老服务端、断网都得能活。
/// 这里守着两条：出厂值不许丢，认不出的东西不许把界面带崩。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('什么都没配的时候用出厂值', () {
    expect(UiConfig.px('fileCard.height'), 80);
    expect(UiConfig.px('fileCard.compactHeight'), 56);
    expect(UiConfig.px('fileCard.padV'), 2);
    expect(UiConfig.str('threadCard.tagSide'), 'leftOfTime');
  });

  test('缓存里有脏数据也照常用，认识的键才生效', () async {
    SharedPreferences.setMockInitialValues({
      'ui_spec_cache':
          '{"rev":3,"values":{"fileCard.height":"120","fileCard.padV":null,"fileCard.nonsense":1}}',
    });
    // Api 没配地址，load 里那次请求会失败，这正是要测的：只吃缓存也能走完
    await UiConfig.load();

    expect(UiConfig.rev, 3);
    expect(UiConfig.px('fileCard.height'), 120); // 字符串数字也认
    expect(UiConfig.px('fileCard.padV'), 2); // null 退回出厂值
    expect(UiConfig.px('fileCard.nonsense'), 0); // 未知键连默认值都没有
  });

  testWidgets('后台给的高度真的画到卡片上', (tester) async {
    SharedPreferences.setMockInitialValues({
      'ui_spec_cache':
          '{"rev":9,"values":{"fileCard.height":100,"fileCard.compactHeight":60,"fileCard.compactWidth":180}}',
    });
    await UiConfig.load();

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: FileCards(
              compact: true,
              files: [
                PostFile(url: '/f/0123456789abcdef0123', name: 'a.zip', size: 2048),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    // FileCards 外面还有一层 Padding，量里面那张卡片本身
    // compact（私信气泡里）走 compactHeight，跟详情页那张大卡互不牵连
    final size = tester.getSize(find.byType(InkWell));
    expect(size.height, 60);
    expect(size.width, 180);
  });
}
