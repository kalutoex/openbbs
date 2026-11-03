/// 网页版：图片缓存在浏览器里，账号隔离由浏览器自己做，这里不插手。
class ImgCache {
  static String _scope = 'guest';

  static String get scope => _scope;

  static String get dirName => '';

  static Null get manager => null;

  static void setScope(String s) {
    _scope = s.isEmpty ? 'guest' : s;
  }

  static Future<void> evict(String url) async {}

  static Future<void> clear() async {}
}
