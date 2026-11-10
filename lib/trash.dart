import 'api.dart';
import 'cloud.dart';

/// 「我的」里回收站那颗数字：帖子 + 文件。
class TrashSummary {
  const TrashSummary({
    required this.threads,
    required this.files,
    required this.total,
  });

  final int threads;
  final int files;
  final int total;

  factory TrashSummary.fromJson(Map m) => TrashSummary(
    threads: m['threads'] is int ? m['threads'] as int : 0,
    files: m['files'] is int ? m['files'] as int : 0,
    total: m['total'] is int ? m['total'] as int : 0,
  );
}

/// 回收站里的一条帖子。删的时候回复、点赞、通知都清了，恢复回来是干净一条。
class TrashThread {
  const TrashThread({
    required this.id,
    required this.title,
    required this.excerpt,
    required this.createdAt,
    required this.deletedAt,
    required this.expiresIn,
    required this.replyCount,
    required this.ownerId,
    required this.ownerName,
    required this.ownerHandle,
  });

  final int id;
  final String title;
  final String excerpt;
  final int createdAt;
  final int deletedAt;

  /// 还剩多少秒被清掉。0 = 马上就没。
  final int expiresIn;
  final int replyCount;
  final int ownerId;

  /// 原作者。管理员回收站里用得上。
  final String ownerName;
  final String ownerHandle;

  factory TrashThread.fromJson(Map m) => TrashThread(
    id: (m['id'] ?? 0) as int,
    title: (m['title'] ?? '') as String,
    excerpt: (m['excerpt'] ?? '') as String,
    createdAt: m['created_at'] is int ? m['created_at'] as int : 0,
    deletedAt: m['deleted_at'] is int ? m['deleted_at'] as int : 0,
    expiresIn: m['expires_in'] is int ? m['expires_in'] as int : 0,
    replyCount: m['reply_count'] is int ? m['reply_count'] as int : 0,
    ownerId: m['owner_id'] is int ? m['owner_id'] as int : 0,
    ownerName: '${m['owner_name'] ?? ''}',
    ownerHandle: '${m['owner_handle'] ?? ''}',
  );
}

/// 管理员回收站里的一条文件：云盘那条 + 原主人。
class TrashFile {
  const TrashFile({
    required this.file,
    required this.ownerId,
    required this.ownerName,
    required this.ownerHandle,
    required this.deletedAt,
  });

  final CloudFile file;
  final int ownerId;
  final String ownerName;
  final String ownerHandle;
  final int deletedAt;

  factory TrashFile.fromJson(Map m) => TrashFile(
    file: CloudFile.fromJson(m),
    ownerId: m['owner_id'] is int ? m['owner_id'] as int : 0,
    ownerName: '${m['owner_name'] ?? ''}',
    ownerHandle: '${m['owner_handle'] ?? ''}',
    deletedAt: m['deleted_at'] is int ? m['deleted_at'] as int : 0,
  );
}

class TrashApi {
  static Future<TrashSummary> summary() async =>
      TrashSummary.fromJson(await Api.get('/trash/summary') as Map);

  static Future<List<TrashThread>> threads({
    int page = 1,
    int perPage = 30,
  }) async {
    final m = await Api.get(
      '/trash/threads',
      query: {'page': '$page', 'per_page': '$perPage'},
    ) as Map;
    final raw = (m['items'] as List?) ?? const [];
    return [
      for (final it in raw)
        if (it is Map) TrashThread.fromJson(it),
    ];
  }

  static Future<void> restoreThread(int id) async {
    await Api.post('/trash/threads/$id/restore', const {});
  }

  /// 彻底删。帖子早就从站里消失了，这一步只是把回收站那一行扔掉。
  static Future<void> purgeThread(int id) async {
    await Api.delete('/trash/threads/$id');
  }

  // ---------------------------------------------------------- 管理员回收站

  static Future<List<TrashThread>> adminThreads({
    String q = '',
    int owner = 0,
    int page = 1,
    int perPage = 50,
  }) async {
    final query = {'page': '$page', 'per_page': '$perPage'};
    if (q.trim().isNotEmpty) query['q'] = q.trim();
    if (owner > 0) query['owner'] = '$owner';
    final m = await Api.get('/admin/trash/threads', query: query) as Map;
    final raw = (m['items'] as List?) ?? const [];
    return [
      for (final it in raw)
        if (it is Map) TrashThread.fromJson(it),
    ];
  }

  static Future<List<TrashFile>> adminCloud({
    String q = '',
    int owner = 0,
    int page = 1,
    int perPage = 50,
  }) async {
    final query = {'page': '$page', 'per_page': '$perPage'};
    if (q.trim().isNotEmpty) query['q'] = q.trim();
    if (owner > 0) query['owner'] = '$owner';
    final m = await Api.get('/admin/trash/cloud', query: query) as Map;
    final raw = (m['items'] as List?) ?? const [];
    return [
      for (final it in raw)
        if (it is Map) TrashFile.fromJson(it),
    ];
  }

  static Future<void> adminRestoreCloud(int id) async {
    await Api.post('/admin/trash/cloud/$id/restore', const {});
  }

  static Future<void> adminPurgeCloud(int id) async {
    await Api.delete('/admin/trash/cloud/$id');
  }
}
