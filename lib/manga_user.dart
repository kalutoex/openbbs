import 'api.dart';
import 'manga.dart';
import 'manga_source.dart';

/// 漫画的收藏与阅读记录。
///
/// 和帖子的收藏分开走：帖子是 thread_id，漫画在本地是目录名，
/// 在书源里只有一条源站地址。所以统一用 (kind, ref) 认一本书：
///   kind='local'  ref=磁盘目录名
///   kind='source' ref=源站那本书的 url
///   kind='zmh'    ref=再漫画的漫画 id
///
/// 服务端顺手抄了一份书名和封面，本地删了、源站挂了，记录里也还看得见名字。

class MangaFav {
  final String kind;
  final String ref;
  final int sourceId;
  final String title;
  final String author;
  final String cover;
  final String sourceName;
  final String lastChapter;
  final bool hasNew;
  final int at;

  const MangaFav({
    required this.kind,
    required this.ref,
    required this.sourceId,
    required this.title,
    required this.author,
    required this.cover,
    this.sourceName = '',
    this.lastChapter = '',
    this.hasNew = false,
    required this.at,
  });

  bool get isSource => kind == 'source';
  bool get isZmh => kind == 'zmh';

  /// 三种封面三种来路：本地是 /manga/... 相对路径，书源和再漫画都得
  /// 过 /sources/img 转一道（源站不带 CORS 头，网页版直连是白框）。
  String get coverUrl => cover.isEmpty
      ? ''
      : isSource
          ? srcImage(cover)
          : isZmh
              ? srcImage(cover, referer: 'https://www.zaimanhua.com/')
              : url(cover);

  factory MangaFav.fromJson(Map<String, dynamic> j) => MangaFav(
        kind: '${j['kind'] ?? 'local'}',
        ref: '${j['ref'] ?? ''}',
        sourceId: (j['source_id'] as num?)?.toInt() ?? 0,
        title: '${j['title'] ?? ''}',
        author: '${j['author'] ?? ''}',
        cover: '${j['cover'] ?? ''}',
        sourceName: '${j['source_name'] ?? ''}',
        lastChapter: '${j['last_chapter'] ?? ''}',
        hasNew: j['has_new'] == true,
        at: (j['at'] as num?)?.toInt() ?? 0,
      );
}

class MangaHist {
  final String kind;
  final String ref;
  final int sourceId;
  final String title;
  final String author;
  final String cover;
  final String chapter;
  final String chapterRef;
  final int page;
  final int total;
  final String sourceName;
  final int at;

  const MangaHist({
    required this.kind,
    required this.ref,
    required this.sourceId,
    required this.title,
    required this.author,
    required this.cover,
    required this.chapter,
    required this.chapterRef,
    required this.page,
    required this.total,
    this.sourceName = '',
    required this.at,
  });

  bool get isSource => kind == 'source';
  bool get isZmh => kind == 'zmh';

  String get coverUrl => cover.isEmpty
      ? ''
      : isSource
          ? srcImage(cover)
          : isZmh
              ? srcImage(cover, referer: 'https://www.zaimanhua.com/')
              : url(cover);

  /// 「第 12 话 · 第 3 页」这种，缺哪段就不写哪段。
  String get where {
    final bits = <String>[];
    if (chapter.isNotEmpty) bits.add(chapter);
    if (total > 0) bits.add('${page + 1}/$total');
    return bits.join(' · ');
  }

  factory MangaHist.fromJson(Map<String, dynamic> j) => MangaHist(
        kind: '${j['kind'] ?? 'local'}',
        ref: '${j['ref'] ?? ''}',
        sourceId: (j['source_id'] as num?)?.toInt() ?? 0,
        title: '${j['title'] ?? ''}',
        author: '${j['author'] ?? ''}',
        cover: '${j['cover'] ?? ''}',
        chapter: '${j['chapter'] ?? ''}',
        chapterRef: '${j['chapter_ref'] ?? ''}',
        page: (j['page'] as num?)?.toInt() ?? 0,
        total: (j['total'] as num?)?.toInt() ?? 0,
        sourceName: '${j['source_name'] ?? ''}',
        at: (j['at'] as num?)?.toInt() ?? 0,
      );
}

class MangaUserApi {
  static Future<bool> favState(String kind, String ref) async {
    if (ref.isEmpty) return false;
    try {
      final d = await Api.get('/manga/fav/state',
          query: {'kind': kind, 'ref': ref});
      return (d is Map) && d['fav'] == true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> toggleFav({
    required String kind,
    required String ref,
    int sourceId = 0,
    String title = '',
    String author = '',
    String cover = '',
  }) async {
    final d = await Api.post('/manga/fav', {
      'kind': kind,
      'ref': ref,
      'source_id': sourceId,
      'title': title,
      'author': author,
      'cover': cover,
    });
    return (d is Map) && d['fav'] == true;
  }

  /// 点开一本收藏的连载 = 新话已经看见了，让服务端把基线推到最新。
  /// 基线由服务端算（它自己会去问源站），这里只报个到——两边算法必须一致。
  static Future<void> markSeen(String kind, String ref) async {
    if (ref.isEmpty) return;
    try {
      await Api.post('/manga/fav/seen', {'kind': kind, 'ref': ref});
    } catch (_) {
      // 消红点失败不是大事，下次点开还会再报一次。
    }
  }

  static Future<List<MangaFav>> favs() async {    final d = await Api.get('/manga/favs');
    final list = (d is Map ? (d['list'] as List?) : null) ?? const [];
    return list
        .whereType<Map>()
        .map((e) => MangaFav.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  static Future<List<MangaHist>> hist() async {
    final d = await Api.get('/manga/history');
    final list = (d is Map ? (d['list'] as List?) : null) ?? const [];
    return list
        .whereType<Map>()
        .map((e) => MangaHist.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  /// 记一条阅读进度。翻页会来得很密，调用方自己节流。
  static Future<void> markRead({
    required String kind,
    required String ref,
    int sourceId = 0,
    String title = '',
    String author = '',
    String cover = '',
    String chapter = '',
    String chapterRef = '',
    int page = 0,
    int total = 0,
  }) async {
    if (ref.isEmpty) return;
    try {
      await Api.post('/manga/history', {
        'kind': kind,
        'ref': ref,
        'source_id': sourceId,
        'title': title,
        'author': author,
        'cover': cover,
        'chapter': chapter,
        'chapter_ref': chapterRef,
        'page': page,
        'total': total,
      });
    } catch (_) {
      // 记进度失败不值得吵人，下次翻页还会再发一次。
    }
  }
}

/// 阅读器要知道「这本书是谁」。本地和书源两套模型长得不一样，
/// 这里摊平成一份，省得阅读器里到处 if。
class ReadRef {
  final String kind;
  final String ref;
  final int sourceId;
  final String title;
  final String author;
  final String cover;

  const ReadRef({
    required this.kind,
    required this.ref,
    this.sourceId = 0,
    this.title = '',
    this.author = '',
    this.cover = '',
  });

  static ReadRef fromBook(MangaBook b) => ReadRef(
        kind: 'local',
        ref: b.dir,
        title: b.title,
        author: b.authors,
        cover: b.cover,
      );

  static ReadRef fromSource(SourceBook b) => ReadRef(
        kind: 'source',
        ref: b.url,
        sourceId: b.sourceId,
        title: b.name,
        author: b.author,
        cover: b.cover,
      );
}
