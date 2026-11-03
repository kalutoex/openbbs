import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// 图片磁盘缓存的账号分区。
///
/// 以前所有账号共用 `libCachedImageData`，切一次号统计就翻一倍，
/// 清缓存还会把别人的一起清掉。现在每个账号一个 CacheManager（目录名带作用域），
/// 切号只换 manager，互不干扰。
class ImgCache {
  static String _scope = 'guest';
  static BaseCacheManager? _manager;
  static final _pool = <String, BaseCacheManager>{};

  static String get scope => _scope;

  /// 当前账号的缓存目录名，和 CacheManager 的 key 一致。
  static String get dirName => 'img_$_scope';

  static BaseCacheManager? get manager => _manager;

  static void setScope(String s) {
    final t = (s.isEmpty ? 'guest' : s).replaceAll(
      RegExp(r'[^A-Za-z0-9_]'),
      '_',
    );
    if (t == _scope && _manager != null) return;
    _scope = t;
    _manager = _pool.putIfAbsent(
      t,
      () => CacheManager(
        Config(
          'img_$t',
          stalePeriod: const Duration(days: 7),
          maxNrOfCacheObjects: 600,
        ),
      ),
    );
  }

  static Future<void> evict(String url) async {
    try {
      await _manager?.removeFile(url);
    } catch (_) {}
  }

  static Future<void> clear() async {
    try {
      await _manager?.emptyCache();
    } catch (_) {}
  }
}
