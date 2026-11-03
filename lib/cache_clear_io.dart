import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

import 'disk_cache.dart';
import 'img_cache.dart';

/// 清缓存：接口响应缓存 + 图片缓存，都只算当前账号那一份。
///
/// 只动这两样。登录凭证、服务器地址、外观设置都在别处，清了不会掉登录。
/// 换号不再叠加：每个账号有自己的 `httpcache/<scope>` 和 `img_<scope>` 目录，
/// 统计和清理都只碰当前作用域。
class AppCache {
  static Future<List<Directory>> _dirs() async {
    final out = <Directory>[];
    try {
      final sup = await getApplicationSupportDirectory();
      out.add(Directory('${sup.path}/httpcache/${DiskCache.scope}'));
    } catch (_) {}
    try {
      final tmp = await getTemporaryDirectory();
      if (ImgCache.dirName.isNotEmpty) {
        out.add(Directory('${tmp.path}/${ImgCache.dirName}'));
      }
    } catch (_) {}
    return out;
  }

  /// 旧版本留下的公共缓存目录（所有账号混在一起那种），只用于清理，不计入大小。
  static Future<List<Directory>> _legacyDirs() async {
    final out = <Directory>[];
    try {
      final sup = await getApplicationSupportDirectory();
      final root = Directory('${sup.path}/httpcache');
      if (await root.exists()) out.add(root);
    } catch (_) {}
    try {
      final tmp = await getTemporaryDirectory();
      out.add(Directory('${tmp.path}/libCachedImageData'));
    } catch (_) {}
    return out;
  }

  static Future<int> size() async {
    var total = 0;
    for (final d in await _dirs()) {
      total += await _sizeOf(d);
    }
    return total;
  }

  static Future<int> _sizeOf(Directory d) async {
    if (!await d.exists()) return 0;
    var n = 0;
    try {
      await for (final e in d.list(recursive: true, followLinks: false)) {
        if (e is File) {
          try {
            n += await e.length();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return n;
  }

  static Future<void> clear() async {
    // 内存里的图片先放掉，否则刚清完屏幕上还是旧的。
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    await DiskCache.clear();
    await ImgCache.clear();
    // 兜底：cache_manager 换了目录名的话，直接删当前作用域的目录。
    for (final d in await _dirs()) {
      try {
        if (await d.exists()) await d.delete(recursive: true);
      } catch (_) {}
    }
    // 老版本把所有人的缓存混在 httpcache 根下和 libCachedImageData 里，
    // 顺手清一次，不然清完还占着几兆。
    for (final d in await _legacyDirs()) {
      try {
        if (!await d.exists()) continue;
        if (d.path.endsWith('/httpcache')) {
          // 根目录里只删老格式的响应缓存和空的子目录，别动别的账号。
          await for (final e in d.list(followLinks: false)) {
            if (e is File) {
              try {
                await e.delete();
              } catch (_) {}
            }
          }
        } else {
          await d.delete(recursive: true);
        }
      } catch (_) {}
    }
  }

  /// 1024 → "1.0 KB"
  static String human(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}
