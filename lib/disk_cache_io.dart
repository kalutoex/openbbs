import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 极简响应缓存：把 GET 回来的 JSON 写到本地，断网时拿出来顶一下。
/// 一个星期没用就自己过期。
class DiskCache {
  static Directory? _dir;
  static const int _ttl = 7 * 24 * 3600;

  /// 账号作用域。不同账号的响应各写各的目录，
  /// 否则切号后 /me、/me/following 会读到上一个人的缓存。
  static String _scope = 'guest';

  static String get scope => _scope;

  static void setScope(String s) {
    final t = (s.isEmpty ? 'guest' : s).replaceAll(
      RegExp(r'[^A-Za-z0-9_]'),
      '_',
    );
    if (t == _scope) return;
    _scope = t;
    _dir = null;
  }

  static Future<Directory?> _ensure() async {
    if (_dir != null) return _dir;
    try {
      final base = await getApplicationSupportDirectory();
      final d = Directory('${base.path}/httpcache/$_scope');
      if (!await d.exists()) await d.create(recursive: true);
      _dir = d;
      return d;
    } catch (_) {
      return null;
    }
  }

  /// 键太长，压成一个短文件名，读的时候再核对一遍原键。
  static String _file(String key) {
    var h = 0;
    for (final c in key.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return 'c_${h.toRadixString(16)}.json';
  }

  static Future<void> write(String key, Object? data) async {
    final d = await _ensure();
    if (d == null) return;
    try {
      final f = File('${d.path}/${_file(key)}');
      final at = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await f.writeAsString(jsonEncode({'key': key, 'at': at, 'data': data}));
    } catch (_) {}
  }

  static Future<dynamic> read(String key) async {
    final d = await _ensure();
    if (d == null) return null;
    try {
      final f = File('${d.path}/${_file(key)}');
      if (!await f.exists()) return null;
      final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      if (m['key'] != key) return null;
      final at = (m['at'] ?? 0) as int;
      if (DateTime.now().millisecondsSinceEpoch ~/ 1000 - at > _ttl) {
        return null;
      }
      return m['data'];
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    try {
      final d = await _ensure();
      if (d != null && await d.exists()) await d.delete(recursive: true);
    } catch (_) {}
    _dir = null;
  }
}
