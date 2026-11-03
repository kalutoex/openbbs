import 'package:flutter/painting.dart';

import 'disk_cache.dart';

/// 网页版：缓存归浏览器管，这里只管内存里的图片。
class AppCache {
  static Future<int> size() async => 0;

  static Future<void> clear() async {
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    await DiskCache.clear();
  }

  static String human(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}
