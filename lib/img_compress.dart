import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_image_compress/flutter_image_compress.dart';

/// 上传前的本地压缩。压完再传，服务器只收结果。
///
/// 规则：
///   最长边压到 [maxSide]，质量从 [quality] 起，超过 [sizeLimit] 就逐级往下
///   降质量，最低 55。GIF 不动，动了就成静态图了。
class ImgCompress {
  static const int maxSide = 1600;
  static const int quality = 82;
  static const int sizeLimit = 600 * 1024;

  /// 静态图上传硬上限 5MB；gif / webp 动图放宽到 10MB，动图压不了只能原样传。
  static const int stillMax = 5 * 1024 * 1024;
  static const int animMax = 10 * 1024 * 1024;

  /// 超了就别传了。动图按动图的尺子量。
  static bool tooBig(Uint8List b) =>
      b.length > (isAnim(b) ? animMax : stillMax);

  /// gif 或者 webp（含动图）都算动图。
  static bool isAnim(Uint8List b) {
    if (_isGif(b)) return true;
    return b.length > 12 &&
        b[0] == 0x52 &&
        b[1] == 0x49 &&
        b[2] == 0x46 &&
        b[3] == 0x46 &&
        b[8] == 0x57 &&
        b[9] == 0x45 &&
        b[10] == 0x42 &&
        b[11] == 0x50;
  }

  /// 压完的字节；压不动就返回原图。
  static Future<Uint8List> run(
    Uint8List src, {
    int maxSide = ImgCompress.maxSide,
    int quality = ImgCompress.quality,
    int sizeLimit = ImgCompress.sizeLimit,
  }) async {
    if (_isGif(src)) return src;

    final (w, h) = await _size(src);
    int tw = w, th = h;
    if (w > 0 && h > 0) {
      final longest = w > h ? w : h;
      if (longest > maxSide) {
        final s = maxSide / longest;
        tw = (w * s).round();
        th = (h * s).round();
      }
    } else {
      tw = maxSide;
      th = maxSide;
    }

    var q = quality;
    var out = await _enc(src, tw, th, q);
    while (out != null && out.length > sizeLimit && q > 55) {
      q -= 12;
      final again = await _enc(src, tw, th, q);
      if (again == null) break;
      out = again;
    }
    if (out == null || out.isEmpty) return src;
    return out.length < src.length ? out : src;
  }

  static Future<Uint8List?> _enc(Uint8List src, int w, int h, int q) async {
    try {
      return await FlutterImageCompress.compressWithList(
        src,
        minWidth: w,
        minHeight: h,
        quality: q,
        format: CompressFormat.jpeg,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<(int, int)> _size(Uint8List src) async {
    try {
      final codec = await ui.instantiateImageCodec(src);
      final frame = await codec.getNextFrame();
      final w = frame.image.width;
      final h = frame.image.height;
      frame.image.dispose();
      codec.dispose();
      return (w, h);
    } catch (_) {
      return (0, 0);
    }
  }

  static bool _isGif(Uint8List b) =>
      b.length > 3 && b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46;

  static String kb(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)}MB';
    }
    return '${(bytes / 1024).round()}KB';
  }
}
