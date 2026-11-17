import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'store.dart' show MangaPref;

/// 一个书签：某本书某一话的某一页。
///
/// 位置沿用「继续阅读」那套相对路径（书目录 + 话目录 + 页码），
/// 换台设备、重装都还认得。
class MangaBookmark {
  final String chDir;
  final String chName;
  final int page;
  final int at;

  const MangaBookmark({
    required this.chDir,
    required this.chName,
    required this.page,
    required this.at,
  });

  bool isAt(String dir, int p) => chDir == dir && page == p;

  Map<String, dynamic> toJson() => {
    'd': chDir,
    'n': chName,
    'p': page,
    't': at,
  };

  static MangaBookmark? fromJson(dynamic j) {
    if (j is! Map) return null;
    final d = j['d'];
    if (d is! String || d.isEmpty) return null;
    final p = (j['p'] as num?)?.toInt() ?? 0;
    if (p < 0) return null;
    return MangaBookmark(
      chDir: d,
      chName: (j['n'] as String?) ?? '',
      page: p,
      at: (j['t'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 书签的存取。key 带「站 + 人」，和阅读位置同一套作用域：
/// A 号标了书签，换个号登进来看同一本书不该看见别人的。
class MangaBm {
  /// 一本书最多留多少条。漫迷标得再多也就几百，超过就丢最老的。
  static const cap = 200;

  static String keyOf(String dir) => 'manga_bm_${MangaPref.scope}_$dir';

  static String _prefix() => 'manga_bm_${MangaPref.scope}_';

  static Future<List<MangaBookmark>> list(String dir) async {
    final sp = await SharedPreferences.getInstance();
    return _read(sp.getString(keyOf(dir)));
  }

  static Future<bool> has(String dir, String chDir, int page) async {
    final all = await list(dir);
    return all.any((b) => b.isAt(chDir, page));
  }

  /// 这一点有书签就删掉，没有就加上。返回加完之后的整表。
  static Future<List<MangaBookmark>> toggle({
    required String dir,
    required String chDir,
    required String chName,
    required int page,
  }) async {
    final all = await list(dir);
    final i = all.indexWhere((b) => b.isAt(chDir, page));
    if (i >= 0) {
      all.removeAt(i);
    } else {
      all.insert(
        0,
        MangaBookmark(
          chDir: chDir,
          chName: chName,
          page: page,
          at: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      if (all.length > cap) all.removeRange(cap, all.length);
    }
    await _write(dir, all);
    return all;
  }

  static Future<List<MangaBookmark>> remove({
    required String dir,
    required String chDir,
    required int page,
  }) async {
    final all = await list(dir);
    all.removeWhere((b) => b.isAt(chDir, page));
    await _write(dir, all);
    return all;
  }

  /// 所有书上的书签，最新的在前。给「书签」汇总页用。
  static Future<Map<String, List<MangaBookmark>>> all() async {
    final sp = await SharedPreferences.getInstance();
    final pre = _prefix();
    final out = <String, List<MangaBookmark>>{};
    for (final k in sp.getKeys()) {
      if (!k.startsWith(pre)) continue;
      final dir = k.substring(pre.length);
      if (dir.isEmpty) continue;
      final bs = _read(sp.getString(k));
      if (bs.isNotEmpty) out[dir] = bs;
    }
    return out;
  }

  /// 删光某本书的书签。删离线文件时顺手调一下，别留一堆点不动的。
  static Future<void> clear(String dir) async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(keyOf(dir));
  }

  static Future<void> _write(String dir, List<MangaBookmark> bs) async {
    final sp = await SharedPreferences.getInstance();
    if (bs.isEmpty) {
      await sp.remove(keyOf(dir));
      return;
    }
    await sp.setString(
      keyOf(dir),
      jsonEncode([for (final b in bs) b.toJson()]),
    );
  }

  static List<MangaBookmark> _read(String? raw) {
    if (raw == null || raw.isEmpty) return <MangaBookmark>[];
    try {
      final m = jsonDecode(raw);
      if (m is! List) return <MangaBookmark>[];
      return m.map(MangaBookmark.fromJson).whereType<MangaBookmark>().toList();
    } catch (_) {
      // 存坏了当没有，下次写会盖掉；别让一行坏数据把书签页搞崩。
      return <MangaBookmark>[];
    }
  }
}
