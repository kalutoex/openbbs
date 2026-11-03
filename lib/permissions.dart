import 'dart:io';

import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 权限都收在这儿。
/// 联网（INTERNET）是安装时系统直接给的，运行时没有弹窗，所以这里只管通知和相册。
class AppPerms {
  static const _askedKey = 'perm_asked_v1';

  /// 通知在前：回复、点赞提醒都靠它；相册用来发图。
  static const List<Permission> list = [
    Permission.notification,
    Permission.photos,
  ];

  static String label(Permission p) =>
      p == Permission.notification ? '通知' : '相册';

  static String subtitle(Permission p) =>
      p == Permission.notification ? '有人回复、赞你时提醒你' : '发帖、回复时从相册选图';

  static Future<Map<Permission, PermissionStatus>> statuses() async {
    final out = <Permission, PermissionStatus>{};
    for (final p in list) {
      out[p] = await p.status;
    }
    return out;
  }

  /// 第一次启动问一遍。问过就记下来，不再每次开都烦人；
  /// 之后想开想关，去设置页里的「权限」。
  static Future<void> firstRun() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    final sp = await SharedPreferences.getInstance();
    if (sp.getBool(_askedKey) == true) return;
    for (final p in list) {
      final s = await p.status;
      if (s.isDenied) {
        await p.request();
      }
    }
    await sp.setBool(_askedKey, true);
  }

  /// 点一下：还能问就再问，系统不给问了就送去应用设置。
  static Future<PermissionStatus> ask(Permission p) async {
    var s = await p.status;
    if (s.isGranted) return s;
    if (s.isPermanentlyDenied || s.isRestricted) {
      await openAppSettings();
      return await p.status;
    }
    s = await p.request();
    return s;
  }

  static String text(PermissionStatus s) {
    if (s.isGranted || s.isLimited) return '已允许';
    if (s.isPermanentlyDenied) return '已拒绝 · 去系统设置开';
    if (s.isRestricted) return '被系统限制';
    return '未允许 · 点一下申请';
  }
}
