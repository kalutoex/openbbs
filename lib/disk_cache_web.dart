/// 网页版走浏览器自己的缓存，这里全是空实现。
class DiskCache {
  static String scope = 'guest';

  static void setScope(String s) {
    scope = s.isEmpty ? 'guest' : s;
  }

  static Future<void> write(String key, Object? data) async {}

  static Future<dynamic> read(String key) async => null;

  static Future<void> clear() async {}
}
