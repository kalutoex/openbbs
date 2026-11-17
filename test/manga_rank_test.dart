import 'package:flutter_test/flutter_test.dart';
import 'package:openbbs/manga_user.dart';
import 'package:openbbs/zmh.dart';

void main() {
  group('榜单解析', () {
    test('正常一页：字段照搬，error 是 false', () {
      final page = ZmhApi.parseRank({
        'type': '0',
        'page': 1,
        'list': [
          {
            'id': 19526,
            'title': '大理寺日志',
            'authors': 'RC',
            'types': '历史',
            'status': '连载中',
            'cover': 'https://x/1.jpg',
            'last': '第323话',
            'updated': 1793457091,
          },
        ],
      });
      expect(page.error, isFalse);
      expect(page.list.length, 1);
      expect(page.list.first.id, 19526);
      expect(page.list.first.title, '大理寺日志');
      expect(page.list.first.last, '第323话');
    });

    test('后端取不到源站：空列表 + error=true，界面才知道该提示重试', () {
      final page = ZmhApi.parseRank({
        'type': '2',
        'page': 1,
        'list': [],
        'error': true,
      });
      expect(page.list, isEmpty);
      expect(page.error, isTrue);
    });

    test('id 缺失、书名空的条目直接剔掉，别让空格子占位', () {
      final page = ZmhApi.parseRank({
        'list': [
          {'id': 0, 'title': '没 id'},
          {'id': 7, 'title': ''},
          {'id': 8, 'title': '好书'},
          'not a map',
          null,
        ],
      });
      expect(page.list.map((b) => b.id), [8]);
    });

    test('返回的不是 map（反代给了个 HTML）也不炸', () {
      expect(ZmhApi.parseRank('<html>').list, isEmpty);
      expect(ZmhApi.parseRank(null).list, isEmpty);
    });

    test('三个榜的顺序和文案是跟服务端 rank_type 绑的', () {
      expect(ZmhApi.rankTabs.map((t) => t.$1), ['0', '1', '2']);
      expect(ZmhApi.rankTabs.map((t) => t.$2), ['人气', '最新', '好评']);
    });
  });

  group('收藏条目', () {
    test('老服务端不带追更字段：按「没有新话」处理，不冒红点', () {
      final f = MangaFav.fromJson({
        'kind': 'zmh',
        'ref': '85702',
        'title': '和她做不成',
        'at': 1794776145,
      });
      expect(f.hasNew, isFalse);
      expect(f.lastChapter, '');
      expect(f.kind, 'zmh');
    });

    test('新话标记和最新章节都读得出来', () {
      final f = MangaFav.fromJson({
        'kind': 'source',
        'ref': 'https://a/b',
        'source_id': 3,
        'source_name': '某源',
        'last_chapter': '第48话',
        'has_new': true,
        'at': 1,
      });
      expect(f.hasNew, isTrue);
      expect(f.lastChapter, '第48话');
      expect(f.sourceId, 3);
      expect(f.sourceName, '某源');
    });

    test('has_new 只认 true，别的怪值都当没有', () {
      expect(MangaFav.fromJson({'has_new': 1}).hasNew, isFalse);
      expect(MangaFav.fromJson({'has_new': 'true'}).hasNew, isFalse);
    });
  });
}
