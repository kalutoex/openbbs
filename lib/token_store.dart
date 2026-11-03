import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 登录令牌的落盘位置。
///
/// 安卓走 Keystore 支持的 secure storage：清理后台、系统回收进程之后仍能读回来，
/// 也不吃 shared_preferences 写盘失败那套问题。网页版没有 Keystore，仍旧用 prefs。
/// 两边都写一份：secure 读失败时还能退回 prefs，不至于把用户踢下线。
class TokenStore {
  static const _key = 'token';

  static const FlutterSecureStorage _s = FlutterSecureStorage(
    aOptions: AndroidOptions(),
  );

  static Future<String?> read() async {
    if (!kIsWeb) {
      try {
        final t = await _s.read(key: _key);
        if (t != null && t.isNotEmpty) return t;
      } catch (_) {
        // Keystore 出问题就当没有，往下走 prefs
      }
    }
    final p = await SharedPreferences.getInstance();
    final t = p.getString(_key);
    if (t != null && t.isNotEmpty) {
      // 旧版本留下的令牌：搬到 secure storage
      if (!kIsWeb) {
        try {
          await _s.write(key: _key, value: t);
        } catch (_) {}
      }
      return t;
    }
    return null;
  }

  static Future<void> write(String token) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, token);
    if (!kIsWeb) {
      try {
        await _s.write(key: _key, value: token);
      } catch (_) {}
    }
  }

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_key);
    if (!kIsWeb) {
      try {
        await _s.delete(key: _key);
      } catch (_) {}
    }
  }
}
