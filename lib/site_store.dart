// 站点表的落盘位置。就一个 JSON 数组，放在 shared_preferences 里。
//
// 没有敏感数据（token 在 token_store / Keystore），不需要 secure storage。
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'sites.dart';

class SiteStore {
  static const _key = 'sites_v1';

  static List<SiteEntry> parse(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return [];
      return list
          .whereType<Map<String, dynamic>>()
          .map(SiteEntry.fromJson)
          .where((s) => s.valid)
          .toList();
    } catch (_) {
      // 存坏了就当空表，启动流程不能跟着挂。
      return [];
    }
  }

  static Future<List<SiteEntry>> read() async {
    final p = await SharedPreferences.getInstance();
    return parse(p.getString(_key));
  }

  static Future<void> write(List<SiteEntry> sites) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(sites.map((s) => s.toJson()).toList()));
  }
}
