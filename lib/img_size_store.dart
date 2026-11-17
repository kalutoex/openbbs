import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Size;

import 'package:flutter/painting.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 记住每张图解码后的宽高。
///
/// 帖子列表滑到有图的楼层时，占位块要是不知道真实比例，就先按 4:3 摆，
/// 图一解码完再撑成 16:9 或者竖图——那一瞬间的跳动就是「卡一下」的来源。
/// 这里存一次，下次直接用真实比例摆，加载前后尺寸不变。
class ImgSizeStore {
  static const _key = 'img_sizes';
  static const _max = 800;

  static final Map<String, Size> _mem = {};
  static bool _loaded = false;
  static Timer? _flush;

  static Size? get(String url) => _mem[url];

  /// 读漫画时要用尺寸估算纵向滚动位置，但 get 是同步的——先等这份表落进内存。
  static Future<void> ensureLoaded() => _load();

  static Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_key);
      if (raw == null || raw.isEmpty) return;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      m.forEach((k, v) {
        if (v is List && v.length == 2) {
          _mem[k] = Size((v[0] as num).toDouble(), (v[1] as num).toDouble());
        }
      });
    } catch (_) {
      // 存坏了就当没有，别让这件事影响看图。
    }
  }

  static Future<void> put(String url, Size s) async {
    if (s.width <= 0 || s.height <= 0) return;
    final old = _mem[url];
    if (old != null && old.width == s.width && old.height == s.height) return;
    await _load();
    _mem[url] = s;
    // 攒一下再落盘：一屏十几张图，逐张写会卡主线程。
    _flush?.cancel();
    _flush = Timer(const Duration(seconds: 3), _write);
  }

  static Future<void> _write() async {
    try {
      var entries = _mem.entries.toList();
      if (entries.length > _max) {
        // Map 保插入序，砍掉最早的那批。
        entries = entries.sublist(entries.length - _max);
        _mem
          ..clear()
          ..addEntries(entries);
      }
      final sp = await SharedPreferences.getInstance();
      await sp.setString(
        _key,
        jsonEncode({
          for (final e in entries)
            e.key: [e.value.width.round(), e.value.height.round()],
        }),
      );
    } catch (_) {}
  }
}
