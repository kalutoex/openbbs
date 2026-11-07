import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'store.dart';

/// 帖子读到哪儿了。
///
/// 只记 post id 和楼层号，别的都不碰。下次点进同一个帖子，直接落回那一层，
/// 不用从第 1 楼重新往下划。
///
/// 过期时间一周：隔一个月回来还跳回第 87 层，人只会觉得莫名其妙。
/// 第 1、2 层不记——等于没读过，记了反而多一次定位请求。
class ReadPos {
  /// 以前是一个 key 装所有站所有账号的位置。站点 A 的 56 号帖读到 87 层，
  /// 切到站点 B 点开自己的 56 号帖，直接落到 87 层——要么落不到，要么落到
  /// 一个完全无关的楼层。帖子编号是小站各自编的，只有「站 + 人」才算同一篇。
  static String get _k {
    final st = AppState.instance;
    final site = st.activeKey.isEmpty ? 'default' : st.activeKey;
    final who = st.uid == 0 ? 'guest' : 'u${st.uid}';
    return 'thread_read_pos_v2_${site}_$who';
  }

  static const _ttl = 7 * 24 * 3600 * 1000;

  /// 表里最多留这么多帖子，超了按时间丢最旧的，别让它无限长。
  static const _cap = 200;

  static Future<Map<String, dynamic>?> get(int threadId) async {
    if (threadId <= 0) return null;
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_k);
    if (raw == null || raw.isEmpty) return null;
    try {
      final all = jsonDecode(raw);
      if (all is! Map) return null;
      final e = all['$threadId'];
      if (e is! Map) return null;
      final at = (e['at'] as num?)?.toInt() ?? 0;
      if (DateTime.now().millisecondsSinceEpoch - at > _ttl) return null;
      final id = (e['id'] as num?)?.toInt() ?? 0;
      final floor = (e['floor'] as num?)?.toInt() ?? 0;
      if (id <= 0 || floor <= 2) return null;
      return {'id': id, 'floor': floor};
    } catch (_) {
      return null;
    }
  }

  static Future<void> put(int threadId, int postId, int floor) async {
    if (threadId <= 0 || postId <= 0 || floor <= 2) return;
    final sp = await SharedPreferences.getInstance();
    final all = _read(sp);
    all['$threadId'] = {
      'id': postId,
      'floor': floor,
      'at': DateTime.now().millisecondsSinceEpoch,
    };
    if (all.length > _cap) {
      final keys = all.keys.toList()
        ..sort((a, b) {
          final aa = ((all[a] as Map)['at'] as num?)?.toInt() ?? 0;
          final bb = ((all[b] as Map)['at'] as num?)?.toInt() ?? 0;
          return bb.compareTo(aa);
        });
      for (final k in keys.skip(_cap)) {
        all.remove(k);
      }
    }
    await sp.setString(_k, jsonEncode(all));
  }

  static Future<void> clear(int threadId) async {
    final sp = await SharedPreferences.getInstance();
    final all = _read(sp);
    if (all.remove('$threadId') == null) return;
    await sp.setString(_k, jsonEncode(all));
  }

  static Map<String, dynamic> _read(SharedPreferences sp) {
    final raw = sp.getString(_k);
    if (raw == null || raw.isEmpty) return {};
    try {
      final m = jsonDecode(raw);
      if (m is Map) return m.cast<String, dynamic>();
    } catch (_) {
      // 存坏了就当没有，下次写会盖掉
    }
    return {};
  }
}
