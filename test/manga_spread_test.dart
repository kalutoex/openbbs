import 'package:flutter_test/flutter_test.dart';
import 'package:openbbs/manga_spread.dart';

void main() {
  test('一屏几页：条漫和拆页时永远一页', () {
    expect(MangaSpread.per(spread: true, vertical: false, split: false), 2);
    expect(MangaSpread.per(spread: true, vertical: true, split: false), 1);
    expect(MangaSpread.per(spread: true, vertical: false, split: true), 1);
    expect(MangaSpread.per(spread: false, vertical: false, split: false), 1);
  });

  test('屏数与页码来回换', () {
    expect(MangaSpread.screens(45, 1), 45);
    expect(MangaSpread.screens(45, 2), 23);
    expect(MangaSpread.screens(46, 2), 23);
    for (final per in [1, 2]) {
      for (var p = 0; p < 46; p++) {
        final s = MangaSpread.screenOf(p, per);
        expect(s, lessThan(MangaSpread.screens(46, per)));
        // 屏号换回页码：落在这一屏的头一页，别越过 p。
        final back = MangaSpread.pageOf(s, per);
        expect(back <= p, isTrue);
        expect(p - back < per, isTrue);
      }
    }
  });

  test('底栏页码：双页显示范围，最后一页不越界', () {
    expect(MangaSpread.label(11, 45, 1), '12 / 45');
    expect(MangaSpread.label(11, 45, 2), '12-13 / 45');
    // 最后一屏只剩一页：显示单个页码，不写成 45-46。
    expect(MangaSpread.label(44, 45, 2), '45 / 45');
    expect(MangaSpread.label(0, 0, 2), '1 / 0');
  });
}
