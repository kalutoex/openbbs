import 'api.dart';
import 'manga_source.dart' show srcImage;

/// 再漫画的书。和书源那套（legado）不是一条路：
/// 那边的规则在前端不用管，这里是服务端直连接口，字段是固定的。
///
/// 好处是不用下载——点开就进详情，翻页时现取图，服务端转一道给浏览器。
class ZmhBook {
  final int id;
  final String title;
  final String authors;
  final String types;
  final String status;
  final String cover;
  final String last;
  final String fromRank;

  const ZmhBook({
    required this.id,
    required this.title,
    this.authors = '',
    this.types = '',
    this.status = '',
    this.cover = '',
    this.last = '',
    this.fromRank = '',
  });

  /// 封面走服务端透传：源站不带 CORS 头，网页版直连画不出来。
  String get coverUrl => srcImage(cover, referer: 'https://www.zaimanhua.com/');

  factory ZmhBook.fromJson(Map<String, dynamic> j) => ZmhBook(
        id: (j['id'] as num?)?.toInt() ?? 0,
        title: '${j['title'] ?? ''}',
        authors: '${j['authors'] ?? ''}',
        types: '${j['types'] ?? ''}',
        status: '${j['status'] ?? ''}',
        cover: '${j['cover'] ?? ''}',
        last: '${j['last'] ?? ''}',
        fromRank: '${j['from_rank'] ?? ''}',
      );
}

class ZmhChapter {
  final int id;
  final String name;
  final int order;
  final bool fee;

  const ZmhChapter({
    required this.id,
    required this.name,
    this.order = 0,
    this.fee = false,
  });

  factory ZmhChapter.fromJson(Map<String, dynamic> j) => ZmhChapter(
        id: (j['id'] as num?)?.toInt() ?? 0,
        name: '${j['name'] ?? ''}',
        order: (j['order'] as num?)?.toInt() ?? 0,
        fee: j['fee'] == true,
      );
}

class ZmhDetail {
  final int id;
  final String title;
  final String authors;
  final String types;
  final String status;
  final String desc;
  final String cover;
  final List<ZmhChapter> chapters;

  const ZmhDetail({
    required this.id,
    required this.title,
    this.authors = '',
    this.types = '',
    this.status = '',
    this.desc = '',
    this.cover = '',
    this.chapters = const [],
  });

  String get coverUrl => srcImage(cover, referer: 'https://www.zaimanhua.com/');

  factory ZmhDetail.fromJson(Map<String, dynamic> j) => ZmhDetail(
        id: (j['id'] as num?)?.toInt() ?? 0,
        title: '${j['title'] ?? ''}',
        authors: '${j['authors'] ?? ''}',
        types: '${j['types'] ?? ''}',
        status: '${j['status'] ?? ''}',
        desc: '${j['desc'] ?? ''}',
        cover: '${j['cover'] ?? ''}',
        chapters: ((j['chapters'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => ZmhChapter.fromJson(e.cast<String, dynamic>()))
            .toList(),
      );
}

class ZmhApi {
  static const _ref = 'https://www.zaimanhua.com/';

  /// 首页推荐。后端挂了就返回空，推荐位本来就可以没有。
  static Future<List<ZmhBook>> recommend({int limit = 18}) async {
    try {
      final d = await Api.get('/manga/recommend', query: {'limit': '$limit'});
      final list = (d is Map ? (d['list'] as List?) : null) ?? const [];
      return list
          .whereType<Map>()
          .map((e) => ZmhBook.fromJson(e.cast<String, dynamic>()))
          .where((b) => b.id > 0 && b.title.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<List<ZmhBook>> search(String q, {int page = 1}) async {
    final d = await Api.get('/manga/zmh/search',
        query: {'q': q, 'page': '$page'}, timeout: const Duration(seconds: 25));
    final list = (d is Map ? (d['list'] as List?) : null) ?? const [];
    return list
        .whereType<Map>()
        .map((e) => ZmhBook.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  static Future<ZmhDetail> detail(int cid) async {
    final d = await Api.get('/manga/zmh/detail/$cid',
        timeout: const Duration(seconds: 25));
    return ZmhDetail.fromJson((d as Map).cast<String, dynamic>());
  }

  /// 一话的图，已换成走后端的地址。
  static Future<List<String>> pages(int cid, int chid) async {
    final d = await Api.get('/manga/zmh/pages/$cid/$chid',
        timeout: const Duration(seconds: 30));
    final list = (d is Map ? (d['pages'] as List?) : null) ?? const [];
    return list
        .map((e) => srcImage('$e', referer: _ref))
        .where((e) => e.isNotEmpty)
        .toList();
  }
}
