import 'package:flutter_test/flutter_test.dart';
import 'package:openbbs/manga.dart';

void main() {
  group('书架请求串', () {
    test('不带参数时和以前一模一样：只有 offset 和 limit', () {
      expect(MangaApi.shelfQuery(offset: 0, limit: 12),
          '?offset=0&limit=12');
      expect(MangaApi.shelfQuery(offset: 24, limit: 12),
          '?offset=24&limit=12');
    });

    test('limit <= 0 是全量，不带任何参数', () {
      expect(MangaApi.shelfQuery(offset: 0, limit: 0), '');
      expect(MangaApi.shelfQuery(offset: 9, limit: -1, sort: 'title'),
          '?sort=title');
    });

    test('recent 不写进串里，别的排序照写', () {
      expect(MangaApi.shelfQuery(sort: 'recent'), '?offset=0&limit=12');
      expect(MangaApi.shelfQuery(sort: 'title'), '?offset=0&limit=12&sort=title');
      expect(MangaApi.shelfQuery(sort: 'progress'),
          '?offset=0&limit=12&sort=progress');
    });

    test('中文搜索词要编码，空格要去掉', () {
      final s = MangaApi.shelfQuery(q: ' 花薰 ');
      expect(s.contains('q=%E8%8A%B1%E8%96%B0'), isTrue,
          reason: '中文没编码，服务器会当成坏请求：$s');
      expect(s.contains(' '), isFalse);
      expect(MangaApi.shelfQuery(q: '   '), '?offset=0&limit=12',
          reason: '只有空格等于没搜');
    });

    test('筛选状态单独传，不传就是全部', () {
      final s = MangaApi.shelfQuery(status: '连载');
      expect(s.contains('status=%E8%BF%9E%E8%BD%BD'), isTrue, reason: s);
    });
  });

  group('进度解析', () {
    Map<String, dynamic> book(Map<String, dynamic>? progress) => {
          'id': '84861',
          'dir': '84861_x',
          'title': '书名',
          'chapter_count': 35,
          'last_chapter': '第35话',
          'progress': ?progress,
        };

    test('没读过 / 未登录：progress 是 null，卡片该显示话数', () {
      final b = MangaBook.fromJson(book(null));
      expect(b.progress, isNull);
      expect(b.chapterCount, 35);
      expect(b.lastChapter, '第35话');
    });

    test('读过：话名、下标、百分比都接上', () {
      final b = MangaBook.fromJson(book({
        'chapter': '第26话',
        'chapter_ref': '0300_第26话',
        'chapter_index': 28,
        'chapter_count': 35,
        'page': 0,
        'total': 14,
        'percent': 0.802,
        'viewed_at': 1794820953,
      }));
      final p = b.progress!;
      expect(p.chapter, '第26话');
      expect(p.chapterRef, '0300_第26话');
      expect(p.chapterIndex, 28);
      expect(p.percent, closeTo(0.802, 0.0001));
      expect(p.label, '第26话 · 80%');
    });

    test('章节表里定位不到（-1）：百分比给 null，标签只说话名', () {
      final b = MangaBook.fromJson(book({
        'chapter': '第3话',
        'chapter_ref': '0003_第3话',
        'chapter_index': -1,
        'chapter_count': 0,
        'page': 2,
        'total': 10,
        'percent': null,
      }));
      expect(b.progress!.chapterIndex, -1);
      expect(b.progress!.percent, isNull);
      expect(b.progress!.label, '第3话');
    });

    test('只有百分比没有说话名时不崩', () {
      final b = MangaBook.fromJson(book({'percent': 0.5}));
      expect(b.progress!.label, '50%');
      expect(b.progress!.chapter, '');
    });

    test('后端给个奇怪的 progress 形状也当没读过，不抛', () {
      expect(MangaBook.fromJson({'dir': 'x', 'progress': 'oops'}).progress, isNull);
      expect(MangaBook.fromJson({'dir': 'x', 'progress': []}).progress, isNull);
    });
  });

  group('分页', () {
    test('还有没有下一页按 total 算', () {
      final page = MangaShelfPage(
        books: List.generate(
            12,
            (i) => MangaBook.fromJson({
                  'id': '$i',
                  'dir': 'd$i',
                  'title': 't$i',
                  'chapter_count': 1,
                  'last_chapter': '',
                })),
        total: 4047,
      );
      expect(page.hasMore(12), isTrue);
      expect(page.hasMore(4047), isFalse);
    });
  });
}
