import 'package:flutter_test/flutter_test.dart';
import 'package:openbbs/manga.dart';
import 'package:openbbs/manga_download.dart';

/// 离线索引的纯逻辑：存回去能不能原样读出来、坏条目会不会带崩整本、
/// 进度怎么算。真落盘那半在手机上，这里不碰文件。
void main() {
  test('一本书连章节一起存成 json 再读回来，文件名一个不差', () {
    final b = MangaDlBook(
      dir: '60778_书名 带空格',
      title: '书名 带空格',
      cover: '/manga/x/cover.webp',
      total: 12,
      at: 123,
    );
    b.chapters['第 1 话'] = MangaDlChapter(
      pages: 3,
      bytes: 900,
      at: 100,
      files: const ['001.jpg', '002.jpg', '003.webp'],
    );
    b.bytes = 900;

    final back = MangaDlBook.fromJson(b.dir, b.toJson())!;
    expect(back.dir, b.dir);
    expect(back.title, b.title);
    expect(back.total, 12);
    expect(back.bytes, 900);
    final ch = back.chapters['第 1 话']!;
    expect(ch.pages, 3);
    expect(ch.files, ['001.jpg', '002.jpg', '003.webp']);
  });

  test('没有文件名的章节条目直接丢掉，不让它变成一话空壳', () {
    final back = MangaDlBook.fromJson('a_b', {
      'title': '书',
      'chs': {
        '第1话': {'pages': 2, 'files': <String>[]},
        '第2话': {'pages': 2, 'files': null},
        '第3话': {'pages': 2, 'files': ['001.jpg']},
      },
    })!;
    expect(back.chapters.keys, ['第3话']);
  });

  test('bytes 没记就按各话加起来，老索引也能读', () {
    final back = MangaDlBook.fromJson('a_b', {
      'chs': {
        '1': {'bytes': 100, 'files': ['001.jpg']},
        '2': {'bytes': 250, 'files': ['001.jpg']},
      },
    })!;
    expect(back.bytes, 350);
  });

  test('整条索引烂掉时 fromJson 不抛，交给上层挪走', () {
    expect(MangaDlBook.fromJson('', {'title': 'x'}), isNull);
    expect(MangaDlBook.fromJson('a_b', 'not a map'), isNull);
    expect(MangaDlBook.fromJson('a_b', null), isNull);
  });

  test('进度按页算；一页都没开始就退回按话算', () {
    final j = MangaDlJob(dir: 'a', title: '书', chaptersTotal: 4);
    expect(j.progress, 0);
    j.chaptersDone = 2;
    expect(j.progress, .5);
    j.pagesTotal = 40;
    j.pagesDone = 10;
    expect(j.progress, .25);
    // 越界不画到条外面去
    j.pagesDone = 60;
    expect(j.progress, 1);
  });

  test('空间估算：有页数用页数，没有按 18 页算', () {
    const a = MangaChapter(id: 1, name: '一', seq: 1, pages: 20, dir: '1');
    const b = MangaChapter(id: 2, name: '二', seq: 2, pages: 0, dir: '2');
    final n = MangaDown.i.estimateBytes([a, b]);
    expect(n, (20 + 18) * 300 * 1024);
  });
}
