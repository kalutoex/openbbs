import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:openbbs/store.dart';

/// 底部 tab 表从 3 个变 4 个（第二个 tab 从板块换成站点）。
/// 老版本存的 1 = 通知、2 = 我的，语义得跟着搬，不能让人的启动页莫名其妙换掉。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<int> load(Map<String, Object> prefs) async {
    SharedPreferences.setMockInitialValues(prefs);
    await AppState.instance.loadPrefs();
    return AppState.instance.startTab.value;
  }

  test('没存过就用首页', () async {
    expect(await load({}), 0);
  });

  test('老键 0 还是首页', () async {
    expect(await load({'start_tab': 0}), 0);
  });

  test('老键 1 原来是通知，换算成新表的 2', () async {
    expect(await load({'start_tab': 1}), 2);
  });

  test('老键 2 原样是「我的」，换算成新表的 3', () async {
    expect(await load({'start_tab': 2}), 3);
  });

  test('新键优先，老键里就算还是 1 也不影响', () async {
    expect(await load({'start_tab': 1, 'start_tab_v2': 1}), 1);
  });

  test('新键越界夹回首页', () async {
    expect(await load({'start_tab_v2': 9}), 3);
  });
}
