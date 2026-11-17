import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openbbs/manga_bookmark.dart';
import 'package:openbbs/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AppState.instance.activeKey = 'main';
    AppState.instance.user = {'id': 7};
  });

  test('加一条、再点同一点就删掉', () async {
    var list = await MangaBm.toggle(
      dir: 'book1',
      chDir: 'ch1',
      chName: '第 1 话',
      page: 3,
    );
    expect(list.length, 1);
    expect(list.first.chName, '第 1 话');
    expect(await MangaBm.has('book1', 'ch1', 3), isTrue);
    expect(await MangaBm.has('book1', 'ch1', 4), isFalse);

    list = await MangaBm.toggle(
      dir: 'book1',
      chDir: 'ch1',
      chName: '第 1 话',
      page: 3,
    );
    expect(list, isEmpty, reason: '同一点再点一次是取消');
    expect(await MangaBm.has('book1', 'ch1', 3), isFalse);
  });

  test('新加的在最前，跨话混着也能分得清', () async {
    await MangaBm.toggle(dir: 'b', chDir: 'c1', chName: '一', page: 0);
    await MangaBm.toggle(dir: 'b', chDir: 'c2', chName: '二', page: 5);
    final l = await MangaBm.list('b');
    expect(l.map((e) => e.chName), ['二', '一']);
    expect(l.first.page, 5);
  });

  test('换个账号看不见别人的书签', () async {
    await MangaBm.toggle(dir: 'b', chDir: 'c', chName: '一', page: 1);
    AppState.instance.user = {'id': 8};
    expect(await MangaBm.list('b'), isEmpty);
    AppState.instance.activeKey = 'other';
    AppState.instance.user = {'id': 7};
    expect(await MangaBm.list('b'), isEmpty, reason: '站点不同也不串');
  });

  test('超过上限丢最老的', () async {
    for (var i = 0; i < MangaBm.cap + 5; i++) {
      await MangaBm.toggle(dir: 'b', chDir: 'c', chName: 'x', page: i);
    }
    final l = await MangaBm.list('b');
    expect(l.length, MangaBm.cap);
    expect(l.any((b) => b.page == 0), isFalse, reason: '最早那条被挤掉');
  });

  test('坏数据当没有，清空后 key 不留', () async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(MangaBm.keyOf('bad'), '[{"d":');
    expect(await MangaBm.list('bad'), isEmpty);

    await MangaBm.toggle(dir: 'bad', chDir: 'c', chName: 'x', page: 2);
    await MangaBm.clear('bad');
    expect(sp.getString(MangaBm.keyOf('bad')), isNull);

    // 手写一条老格式（多一个没用的字段）也读得出来
    await sp.setString(
      MangaBm.keyOf('old'),
      jsonEncode([
        {'d': 'c', 'n': '话', 'p': 2, 't': 1, 'zzz': true},
      ]),
    );
    expect((await MangaBm.list('old')).single.page, 2);
  });

  test('汇总：只收有书签的书', () async {
    await MangaBm.toggle(dir: 'a', chDir: 'c', chName: 'x', page: 0);
    await MangaBm.toggle(dir: 'b', chDir: 'c', chName: 'x', page: 0);
    await MangaBm.toggle(dir: 'b', chDir: 'c', chName: 'x', page: 0);
    final all = await MangaBm.all();
    expect(all.keys.toList()..sort(), ['a']);
  });
}
