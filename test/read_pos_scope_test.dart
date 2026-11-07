import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openbbs/read_pos.dart';
import 'package:openbbs/store.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final st = AppState.instance;
    st.user = {'id': 7};
    st.activeKey = 'a';
  });

  test('阅读位置按账号分开：换个号读不到上一个人的楼层', () async {
    final st = AppState.instance;
    await ReadPos.put(56, 900, 87);
    expect((await ReadPos.get(56))?['floor'], 87);

    st.user = {'id': 8};
    expect(await ReadPos.get(56), isNull);

    // 切回来还是自己的位置
    st.user = {'id': 7};
    expect((await ReadPos.get(56))?['floor'], 87);
  });

  test('阅读位置按站点分开：A 站的 56 号帖不带到 B 站', () async {
    final st = AppState.instance;
    await ReadPos.put(56, 900, 87);
    st.activeKey = 'b';
    expect(await ReadPos.get(56), isNull);

    st.activeKey = 'a';
    expect((await ReadPos.get(56))?['floor'], 87);
  });
}
