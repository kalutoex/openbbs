import 'api.dart';

/// 云盘用量。quota 为 null 表示不限。
class CloudUsage {
  const CloudUsage({
    required this.quota,
    required this.used,
    required this.count,
    required this.trash,
    required this.trashCount,
  });

  final int? quota;
  final int used;
  final int count;
  final int trash;
  final int trashCount;

  factory CloudUsage.fromJson(Map m) => CloudUsage(
        quota: m['quota'] is int ? m['quota'] as int : null,
        used: m['used'] is int ? m['used'] as int : 0,
        count: m['count'] is int ? m['count'] as int : 0,
        trash: m['trash'] is int ? m['trash'] as int : 0,
        trashCount: m['trash_count'] is int ? m['trash_count'] as int : 0,
      );

  bool get unlimited => quota == null || quota == 0;

  int get left => unlimited ? 0 : (quota! - used).clamp(0, quota!);

  double get ratio => unlimited || quota == 0 ? 0 : (used / quota!).clamp(0.0, 1.0);
}

/// 云盘里的一个文件。
class CloudFile {
  const CloudFile({
    required this.id,
    required this.digest,
    required this.name,
    required this.size,
    required this.url,
    required this.source,
    required this.public,
    required this.threadId,
    required this.createdAt,
    required this.refs,
    required this.expiresIn,
  });

  final int id;
  final String digest;
  final String name;
  final int size;
  final String url;

  /// cloud = 自己传的，post = 发帖时一起传的。只做展示，不影响操作。
  final String source;
  final bool public;
  final int? threadId;
  final int createdAt;

  /// 被几个帖子用着。删之前要提示。
  final int refs;

  /// 回收站里还剩多少秒。不在回收站就是 null。
  final int? expiresIn;

  factory CloudFile.fromJson(Map m) => CloudFile(
        id: (m['id'] ?? 0) as int,
        digest: (m['digest'] ?? '') as String,
        name: (m['name'] ?? '') as String,
        size: m['size'] is int ? m['size'] as int : 0,
        url: (m['url'] ?? '') as String,
        source: (m['source'] ?? 'cloud') as String,
        public: m['public'] == true,
        threadId: m['thread_id'] is int ? m['thread_id'] as int : null,
        createdAt:
            m['created_at'] is int ? m['created_at'] as int : 0,
        refs: m['refs'] is int ? m['refs'] as int : 0,
        expiresIn: m['expires_in'] is int ? m['expires_in'] as int : null,
      );

  String get sizeText => bytesText(size);
}

class CloudPage {
  const CloudPage({required this.items, required this.total, required this.page});

  final List<CloudFile> items;
  final int total;
  final int page;
}

String bytesText(int size) {
  if (size >= 1024 * 1024 * 1024) {
    return '${(size / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }
  if (size >= 1024 * 1024) {
    return '${(size / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  if (size >= 1024) return '${(size / 1024).toStringAsFixed(0)} KB';
  return '$size B';
}

class CloudApi {
  static Future<CloudUsage> usage() async =>
      CloudUsage.fromJson(await Api.get('/cloud/usage') as Map);

  static Future<CloudPage> list({
    String q = '',
    String sort = 'time',
    int page = 1,
    int perPage = 20,
  }) async {
    final query = <String, String>{
      'sort': sort,
      'page': '$page',
      'per_page': '$perPage',
    };
    if (q.trim().isNotEmpty) query['q'] = q.trim();
    final m = await Api.get('/cloud/files', query: query) as Map;
    final raw = (m['items'] as List?) ?? const [];
    return CloudPage(
      items: [
        for (final it in raw)
          if (it is Map) CloudFile.fromJson(it)
      ],
      total: m['total'] is int ? m['total'] as int : 0,
      page: m['page'] is int ? m['page'] as int : 1,
    );
  }

  /// 删进回收站。空间还占着，彻底删除才还。
  static Future<Map> remove(int id) async =>
      await Api.delete('/cloud/files/$id') as Map;

  static Future<List<CloudFile>> trash() async {
    final m = await Api.get('/cloud/trash') as Map;
    final raw = (m['items'] as List?) ?? const [];
    return [
      for (final it in raw)
        if (it is Map) CloudFile.fromJson(it)
    ];
  }

  static Future<void> restore(int id) async {
    await Api.post('/cloud/files/$id/restore', const {});
  }

  /// 回收站里彻底删掉，物理文件一起走，找不回来。
  static Future<void> purge(int id) async {
    await Api.delete('/cloud/trash/$id');
  }
}
