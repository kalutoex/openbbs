import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 本机保存过的一个账号。token 是真正的凭证，其余字段只用来在列表里显示。
class Account {
  final String token;
  final int id;
  final String name;
  final String nickname;
  final String handle;
  final String uid;
  final String avatar;

  /// 这个账号的主题色（也是身份色）。null = 没设过。
  final int? hue;

  const Account({
    required this.token,
    required this.id,
    required this.name,
    required this.nickname,
    required this.handle,
    required this.uid,
    required this.avatar,
    this.hue,
  });

  /// 从 /me 返回的 user 里取字段。
  factory Account.fromUser(String token, Map<String, dynamic> u) => Account(
    token: token,
    id: (u['id'] ?? 0) as int,
    name: '${u['name'] ?? ''}',
    nickname: '${u['nickname'] ?? u['name'] ?? ''}',
    handle: '${u['handle'] ?? ''}',
    uid: '${u['uid'] ?? ''}',
    avatar: '${u['avatar'] ?? ''}',
    hue: u['hue'] is int ? u['hue'] as int : null,
  );

  factory Account.fromJson(Map<String, dynamic> j) => Account(
    token: '${j['token'] ?? ''}',
    id: (j['id'] ?? 0) as int,
    name: '${j['name'] ?? ''}',
    nickname: '${j['nickname'] ?? j['name'] ?? ''}',
    handle: '${j['handle'] ?? ''}',
    uid: '${j['uid'] ?? ''}',
    avatar: '${j['avatar'] ?? ''}',
    hue: j['hue'] is int ? j['hue'] as int : null,
  );

  Map<String, dynamic> toJson() => {
    'token': token,
    'id': id,
    'name': name,
    'nickname': nickname,
    'handle': handle,
    'uid': uid,
    'avatar': avatar,
    'hue': hue,
  };

  /// 同一个账号的判定：id 是库里的主键，重登后 token 会换、id 不变。
  bool sameAccount(Account o) => id == o.id;
}

/// 多账号列表的落盘位置。token 属于敏感数据，安卓走 Keystore，
/// 网页版退回 prefs。两边都写一份，读不出来时不至于把账号全丢了。
class AccountStore {
  static const _key = 'accounts';

  static const FlutterSecureStorage _s = FlutterSecureStorage(
    aOptions: AndroidOptions(),
  );

  static List<Account> _parse(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return [];
      return list
          .whereType<Map<String, dynamic>>()
          .map(Account.fromJson)
          .where((a) => a.token.isNotEmpty)
          .toList();
    } catch (_) {
      // 存坏了就当没有，别让启动流程跟着挂
      return [];
    }
  }

  static Future<List<Account>> read() async {
    if (!kIsWeb) {
      try {
        final raw = await _s.read(key: _key);
        final list = _parse(raw);
        if (list.isNotEmpty) return list;
      } catch (_) {
        // Keystore 出问题就往下走 prefs
      }
    }
    final p = await SharedPreferences.getInstance();
    return _parse(p.getString(_key));
  }

  static Future<void> write(List<Account> accounts) async {
    final raw = jsonEncode(accounts.map((a) => a.toJson()).toList());
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, raw);
    if (!kIsWeb) {
      try {
        await _s.write(key: _key, value: raw);
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
