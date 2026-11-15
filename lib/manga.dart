import 'package:flutter/foundation.dart';

import 'api.dart';

/// 本地漫画库（后端扫 /vol2/1000/manga 出来的）。
///
/// 和论坛的帖子是两套东西：漫画不进数据库，就是磁盘上的目录，
/// 接口只负责把目录念成 JSON，图片走 /manga 静态挂载。
class MangaBook {
  final String id;
  final String dir;
  final String title;
  final String authors;
  final String types;
  final String status;
  final String desc;
  final String cover;
  final int chapterCount;
  final String lastChapter;

  const MangaBook({
    required this.id,
    required this.dir,
    required this.title,
    required this.authors,
    required this.types,
    required this.status,
    required this.desc,
    required this.cover,
    required this.chapterCount,
    required this.lastChapter,
  });

  factory MangaBook.fromJson(Map<String, dynamic> j) => MangaBook(
        id: '${j['id'] ?? ''}',
        dir: '${j['dir'] ?? ''}',
        title: '${j['title'] ?? ''}',
        authors: '${j['authors'] ?? ''}',
        types: '${j['types'] ?? ''}',
        status: '${j['status'] ?? ''}',
        desc: '${j['desc'] ?? ''}',
        cover: '${j['cover'] ?? ''}',
        chapterCount: (j['chapter_count'] as num?)?.toInt() ?? 0,
        lastChapter: '${j['last_chapter'] ?? ''}',
      );

  /// 接口返回的是 /manga/... 相对地址，补上站点前缀才能给 Image 用。
  String get coverUrl => url(cover);
}

/// 一页书架数据：这一页的书 + 一共有多少本（用来判断还有没有下一页）。
class MangaShelfPage {
  final List<MangaBook> books;
  final int total;

  const MangaShelfPage({required this.books, required this.total});

  bool hasMore(int loaded) => loaded < total;
}

class MangaChapter {
  final int id;
  final String name;
  final int seq;
  final int pages;
  final String dir;

  const MangaChapter({
    required this.id,
    required this.name,
    required this.seq,
    required this.pages,
    required this.dir,
  });

  factory MangaChapter.fromJson(Map<String, dynamic> j) => MangaChapter(
        id: (j['id'] as num?)?.toInt() ?? 0,
        name: '${j['name'] ?? ''}',
        seq: (j['seq'] as num?)?.toInt() ?? 0,
        pages: (j['pages'] as num?)?.toInt() ?? 0,
        dir: '${j['dir'] ?? ''}',
      );
}

class MangaDetail {
  final String dir;
  final String title;
  final String authors;
  final String types;
  final String status;
  final String desc;
  final String cover;
  final List<MangaChapter> chapters;

  const MangaDetail({
    required this.dir,
    required this.title,
    required this.authors,
    required this.types,
    required this.status,
    required this.desc,
    required this.cover,
    required this.chapters,
  });

  factory MangaDetail.fromJson(Map<String, dynamic> j) => MangaDetail(
        dir: '${j['dir'] ?? ''}',
        title: '${j['title'] ?? ''}',
        authors: '${j['authors'] ?? ''}',
        types: '${j['types'] ?? ''}',
        status: '${j['status'] ?? ''}',
        desc: '${j['desc'] ?? ''}',
        cover: '${j['cover'] ?? ''}',
        chapters: ((j['chapters'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => MangaChapter.fromJson(e.cast<String, dynamic>()))
            .toList(),
      );

  String get coverUrl => url(cover);
}

/// 站点内相对路径拼成绝对地址。网页版同源，App 走当前选中的通道。
String url(String path) {
  if (path.isEmpty) return '';
  if (path.startsWith('http')) return path;
  return '${Api.base}$path';
}

class MangaApi {
  /// 一页书架。limit <= 0 就是全量（老用法留着）。
  ///
  /// 书多了以后一次全发给网页版，光 JSON 就够呛，封面更是排着队下，
  /// 所以书架按页取，滑到底再要下一页。
  static Future<MangaShelfPage> shelf({int offset = 0, int limit = 12}) async {
    final q = limit > 0 ? '?offset=$offset&limit=$limit' : '';
    final d = await Api.get('/manga/shelf$q');
    final list = (d is Map ? (d['list'] as List?) : null) ?? const [];
    final books = list
        .whereType<Map>()
        .map((e) => MangaBook.fromJson(e.cast<String, dynamic>()))
        .toList();
    final total = (d is Map ? (d['total'] as num?)?.toInt() : null) ?? books.length;
    return MangaShelfPage(books: books, total: total);
  }

  static Future<MangaDetail> detail(String dir) async {
    final d = await Api.get('/manga/detail/${Uri.encodeComponent(dir)}');
    return MangaDetail.fromJson((d as Map).cast<String, dynamic>());
  }

  /// 一话的图片地址表（已拼成绝对地址）。
  static Future<List<String>> pages(String dir, String chapterDir) async {
    final d = await Api.get(
      '/manga/chapter/${Uri.encodeComponent(dir)}/'
      '${Uri.encodeComponent(chapterDir)}',
    );
    final list = (d is Map ? (d['pages'] as List?) : null) ?? const [];
    return list.map((e) => url('$e')).toList();
  }
}

/// 书架变化时通知一下，抓完新书回来能自己刷新。
final mangaBump = ValueNotifier<int>(0);
