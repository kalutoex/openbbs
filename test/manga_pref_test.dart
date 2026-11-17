import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openbbs/store.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final st = AppState.instance;
    st.user = {'id': 7};
    st.activeKey = 'a';
  });

  group('漫画阅读偏好', () {
    test('没存过就是用默认：横向翻页、不压暗、页间距为 0', () async {
      expect(await MangaPref.vertical(), isNull, reason: '空 = 没选过，交给页面默认');
      expect(await MangaPref.brightness(), MangaPref.brightMax);
      expect(await MangaPref.gap(), 0);
    });

    test('写进去能读回来', () async {
      await MangaPref.setVertical(true);
      await MangaPref.setBrightness(0.5);
      await MangaPref.setGap(12);
      expect(await MangaPref.vertical(), isTrue);
      expect(await MangaPref.brightness(), 0.5);
      expect(await MangaPref.gap(), 12);
    });

    test('按账号分开：换个号读不到上一个人的亮度', () async {
      final st = AppState.instance;
      await MangaPref.setBrightness(0.4);
      await MangaPref.setVertical(true);

      st.user = {'id': 8};
      expect(
        await MangaPref.brightness(),
        MangaPref.brightMax,
        reason: '新号进阅读器第一眼不该是别人调暗的',
      );
      expect(await MangaPref.vertical(), isNull);

      st.user = {'id': 7};
      expect(await MangaPref.brightness(), 0.4);
    });

    test('按站点分开：A 站的选择不带到 B 站', () async {
      final st = AppState.instance;
      await MangaPref.setGap(16);
      st.activeKey = 'b';
      expect(await MangaPref.gap(), 0);
      st.activeKey = 'a';
      expect(await MangaPref.gap(), 16);
    });

    test('没登录也是一个独立作用域，不跟登录号混', () async {
      final st = AppState.instance;
      await MangaPref.setBrightness(0.6);
      st.user = null;
      expect(await MangaPref.brightness(), MangaPref.brightMax);
    });

    test('越界的值夹回来，别把屏幕弄成全黑', () async {
      await MangaPref.setBrightness(0);
      expect(await MangaPref.brightness(), MangaPref.brightMin);
      await MangaPref.setBrightness(9);
      expect(await MangaPref.brightness(), MangaPref.brightMax);
      await MangaPref.setGap(-5);
      expect(await MangaPref.gap(), 0);
      await MangaPref.setGap(999);
      expect(await MangaPref.gap(), MangaPref.gapMax);
    });

    test('key 里带着站点和账号，能一眼看出是谁的', () {
      expect(MangaPref.keyOf('brightness'), 'manga_read_brightness_a_u7');
    });
  });
}
