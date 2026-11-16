import 'package:flutter/foundation.dart';

import 'api.dart';

/// 一本书读到哪了。后端按请求用户当场查库，未登录时整个字段不出现。
class MangaProgress {
  final String chapter;
  final String chapterRef;

  /// 这一话在章节表里的下标；定位不到就是 -1（老记录、书重新抓过都可能）。
  final int chapterIndex;
  final int chapterCount;
  final int page;

  /// 本话总页数，不是全书话数。
  final int total;
  final double? percent;
  final int viewedAt;

  const MangaProgress({
    required this.chapter,
    required this.chapterRef,
    required this.chapterIndex,
    required this.chapterCount,
    required this.page,
    required this.total,
    required this.percent,
    required this.viewedAt,
  });

  static MangaProgress? fromJson(Object? v) {
    if (v is! Map) return null;
    final j = v.cast<String, dynamic>();
    return MangaProgress(
      chapter: '${j['chapter'] ?? ''}',
      chapterRef: '${j['chapter_ref'] ?? ''}',
      chapterIndex: (j['chapter_index'] as num?)?.toInt() ?? -1,
      chapterCount: (j['chapter_count'] as num?)?.toInt() ?? 0,
      page: (j['page'] as num?)?.toInt() ?? 0,
      total: (j['total'] as num?)?.toInt() ?? 0,
      percent: (j['percent'] as num?)?.toDouble(),
      viewedAt: (j['viewed_at'] as num?)?.toInt() ?? 0,
    );
  }

  /// 卡片上那一行：有章节名就报话数，没有就报百分比。
  String get label {
    final p = percent;
    final pct = p == null ? null : (p * 100).round();
    if (chapter.isNotEmpty && pct != null) return '$chapter · $pct%';
    if (chapter.isNotEmpty) return chapter;
    if (pct != null) return '$pct%';
    return '在读';
  }
}

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

  /// 读到哪了。未登录或没读过就是 null。
  final MangaProgress? progress;

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
    this.progress,
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
        progress: MangaProgress.fromJson(j['progress']),
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

  /// 读到哪了。用于详情页的「继续看」和章节打勾。
  final MangaProgress? progress;

  const MangaDetail({
    required this.dir,
    required this.title,
    required this.authors,
    required this.types,
    required this.status,
    required this.desc,
    required this.cover,
    required this.chapters,
    this.progress,
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
        progress: MangaProgress.fromJson(j['progress']),
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
  ///
  /// sort/status/q 都是后加的：不传时请求和以前一模一样，
  /// 老版本客户端不会因为这些参数被后端拒掉。
  static Future<MangaShelfPage> shelf({
    int offset = 0,
    int limit = 12,
    String sort = 'recent',
    String status = '',
    String q = '',
  }) async {
    final qs = shelfQuery(offset: offset, limit: limit, sort: sort, status: status, q: q);
    final d = await Api.get('/manga/shelf$qs');
    final list = (d is Map ? (d['list'] as List?) : null) ?? const [];
    final books = list
        .whereType<Map>()
        .map((e) => MangaBook.fromJson(e.cast<String, dynamic>()))
        .toList();
    final total = (d is Map ? (d['total'] as num?)?.toInt() : null) ?? books.length;
    return MangaShelfPage(books: books, total: total);
  }

  /// 书架请求的查询串。抽出来是为了能单测——中文书名、空格、
  /// 特殊字符都得编好，不然搜「花薰」会变成一条 400。
  @visibleForTesting
  static String shelfQuery({
    int offset = 0,
    int limit = 12,
    String sort = 'recent',
    String status = '',
    String q = '',
  }) {
    final params = <String, String>{};
    if (limit > 0) {
      params['offset'] = '$offset';
      params['limit'] = '$limit';
    }
    if (sort.isNotEmpty && sort != 'recent') params['sort'] = sort;
    if (status.isNotEmpty) params['status'] = status;
    final key = q.trim();
    if (key.isNotEmpty) params['q'] = key;
    if (params.isEmpty) return '';
    return '?${params.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&')}';
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
