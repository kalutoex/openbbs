import 'api.dart';

/// 书源里的书：还没落到本地，正文和图片都在源站。
///
/// 和书架上的 [MangaBook] 是两码事——书架那是磁盘上真有的目录，
/// 这里是「顺着规则去源站取」，源站挂了就取不到，所以每一条都记着出身。
class SourceBook {
  final int sourceId;
  final String sourceName;
  final String name;
  final String author;
  final String cover;
  final String url;

  const SourceBook({
    required this.sourceId,
    required this.sourceName,
    required this.name,
    required this.author,
    required this.cover,
    required this.url,
  });

  factory SourceBook.fromJson(
    Map<String, dynamic> j, {
    required int sourceId,
    required String sourceName,
  }) => SourceBook(
    sourceId: sourceId,
    sourceName: sourceName,
    name: '${j['name'] ?? ''}',
    author: '${j['author'] ?? ''}',
    cover: '${j['cover'] ?? ''}',
    url: '${j['url'] ?? ''}',
  );

  String get coverUrl => srcImage(cover);

  /// 格子里用的封面，让后端切到 240 宽。
  String get coverThumb => srcImage(cover, w: 240);
}

/// 一个源这一轮搜索的结果。没搜到也是一种结果，得如实标出来。
class SourceGroup {
  final int sourceId;
  final String name;
  final bool ok;
  final String err;
  final int ms;
  final List<SourceBook> books;

  const SourceGroup({
    required this.sourceId,
    required this.name,
    required this.ok,
    required this.err,
    required this.ms,
    required this.books,
  });

  factory SourceGroup.fromJson(Map<String, dynamic> j) {
    final sid = (j['source_id'] as num?)?.toInt() ?? 0;
    final name = '${j['source_name'] ?? ''}';
    return SourceGroup(
      sourceId: sid,
      name: name,
      ok: j['ok'] == true,
      err: '${j['err'] ?? ''}',
      ms: (j['ms'] as num?)?.toInt() ?? 0,
      books: ((j['books'] as List?) ?? const [])
          .whereType<Map>()
          .map(
            (e) => SourceBook.fromJson(
              e.cast<String, dynamic>(),
              sourceId: sid,
              sourceName: name,
            ),
          )
          .where((b) => b.url.isNotEmpty)
          .toList(),
    );
  }
}

class SourceSearch {
  final List<SourceGroup> groups;
  final int ms;
  final int total;

  const SourceSearch({
    required this.groups,
    required this.ms,
    required this.total,
  });

  List<SourceGroup> get hit => groups.where((g) => g.books.isNotEmpty).toList();
  List<SourceGroup> get miss => groups.where((g) => g.books.isEmpty).toList();
}

class SourceChapter {
  final String name;
  final String url;

  const SourceChapter({required this.name, required this.url});

  factory SourceChapter.fromJson(Map<String, dynamic> j) =>
      SourceChapter(name: '${j['name'] ?? ''}', url: '${j['url'] ?? ''}');
}

class SourceBookDetail {
  final String name;
  final String author;
  final String cover;
  final String intro;
  final String kind;
  final String last;
  final List<SourceChapter> chapters;

  const SourceBookDetail({
    required this.name,
    required this.author,
    required this.cover,
    required this.intro,
    required this.kind,
    required this.last,
    required this.chapters,
  });

  factory SourceBookDetail.fromJson(Map<String, dynamic> j) => SourceBookDetail(
    name: '${j['name'] ?? ''}',
    author: '${j['author'] ?? ''}',
    cover: '${j['cover'] ?? ''}',
    intro: '${j['intro'] ?? ''}',
    kind: '${j['kind'] ?? ''}',
    last: '${j['last'] ?? ''}',
    chapters: ((j['chapters'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => SourceChapter.fromJson(e.cast<String, dynamic>()))
        .where((c) => c.name.isNotEmpty)
        .toList(),
  );

  String get coverUrl => srcImage(cover);

  String get coverThumb => srcImage(cover, w: 240);
}

/// 源站的图十有八九查 Referer，还常换域名，浏览器直接拿会 403 或者裂图。
/// 统一从后端过一道：/sources/img 带 UA 和 Referer 去取，转回来。
///
/// 图片标签带不了 Authorization，所以 token 挂在查询串上。
String srcImage(String u, {String referer = '', int w = 0}) {
  if (u.isEmpty) return '';
  final t = Api.token ?? '';
  // w 给了就让后端按这个宽度切一刀，封面用；看图不给，原样转发。
  final wq = w > 0 ? '&w=$w' : '';
  return '${Api.base}/api/sources/img'
      '?u=${Uri.encodeComponent(u)}'
      '&r=${Uri.encodeComponent(referer)}'
      '&t=${Uri.encodeComponent(t)}$wq';
}

class SourceApi {
  /// 所有开着的源一起搜。慢的源后端会丢掉，别指望一个不落。
  static Future<SourceSearch> search(String q, {int type = 2}) async {
    // 二十几个源一起问，慢的到点才回来，别用默认那 15 秒卡死。
    final d = await Api.get(
      '/sources/search',
      query: {'q': q, 'type': '$type'},
      timeout: const Duration(seconds: 30),
    );
    final m = (d as Map).cast<String, dynamic>();
    return SourceSearch(
      groups: ((m['groups'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => SourceGroup.fromJson(e.cast<String, dynamic>()))
          .toList(),
      ms: (m['ms'] as num?)?.toInt() ?? 0,
      total: (m['books'] as num?)?.toInt() ?? 0,
    );
  }

  static Future<SourceBookDetail> detail(int sid, String url) async {
    final d = await Api.get('/sources/$sid/detail', query: {'url': url});
    return SourceBookDetail.fromJson((d as Map).cast<String, dynamic>());
  }

  /// 一话的图片地址，已经换成走后端的地址。
  static Future<List<String>> pages(int sid, String url) async {
    final d = await Api.get('/sources/$sid/pages', query: {'url': url});
    final list = (d is Map ? (d['list'] as List?) : null) ?? const [];
    return list
        .map((e) => srcImage('$e', referer: url))
        .where((e) => e.isNotEmpty)
        .toList();
  }
}
