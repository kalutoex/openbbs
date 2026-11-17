import 'package:flutter_test/flutter_test.dart';
import 'package:openbbs/manga_stats.dart';
import 'package:openbbs/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AppState.instance.activeKey = 'main';
    AppState.instance.user = {'id': 7};
    await MangaStats.clear();
  });

  test('时长、翻页、开话各自累加', () async {
    await MangaStats.addSeconds(90);
    await MangaStats.addSeconds(30);
    await MangaStats.addPage('b1', '书一');
    await MangaStats.addPage('b1', '书一');
    await MangaStats.addPage('b2', '书二');
    await MangaStats.addChapter('b1', '书一');

    final d = await MangaStats.load();
    expect(d.sec, 120);
    expect(d.pages, 3);
    expect(d.chapters, 1);
    expect(d.books['b1']!.pages, 2);
    expect(d.books['b1']!.chapters, 1);
  });

  test('并发写不互相盖掉', () async {
    await Future.wait([
      for (var i = 0; i < 20; i++) MangaStats.addPage('b', '书'),
      for (var i = 0; i < 10; i++) MangaStats.addSeconds(1),
    ]);
    final d = await MangaStats.load();
    expect(d.pages, 20);
    expect(d.sec, 10);
  });

  test('当天那格记的是当天秒数', () async {
    await MangaStats.addSeconds(45);
    final d = await MangaStats.load();
    final k = MangaStatsData.dayKey(DateTime.now());
    expect(d.days[k], 45);
    final week = d.recentDays(7);
    expect(week.length, 7);
    expect(week.last.$1, k);
    expect(week.last.$2, 45);
    expect(week.first.$2, 0, reason: '没读的那天补 0，柱子不能缺格');
  });

  test('最常看的排在前面，没读过的算空', () async {
    for (var i = 0; i < 5; i++) {
      await MangaStats.addPage('hot', '热门');
    }
    await MangaStats.addPage('cold', '冷门');
    final d = await MangaStats.load();
    expect(d.topBooks().first.key, 'hot');
    expect(d.empty, isFalse);
  });

  test('天数只留 30 天', () async {
    final sp = await SharedPreferences.getInstance();
    final days = <String, int>{
      for (var i = 0; i < 40; i++)
        '2026-01-${(i + 1).toString().padLeft(2, '0')}': 10,
    };
    await sp.setString(
      MangaStats.key,
      '{"sec":10,"pages":0,"chapters":0,"days":'
      '${_json(days)},"books":{}}',
    );
    await MangaStats.addSeconds(5);
    final d = await MangaStats.load();
    expect(d.days.length, 30);
    expect(d.days.containsKey('2026-01-01'), isFalse, reason: '最老的先丢');
    expect(d.days.containsKey('2026-01-40'), isTrue);
  });

  test('坏数据当没读过', () async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(MangaStats.key, '{"sec":');
    final d = await MangaStats.load();
    expect(d.empty, isTrue);
  });
}

String _json(Map<String, int> m) =>
    '{${m.entries.map((e) => '"${e.key}":${e.value}').join(',')}}';
