import 'package:flutter/services.dart';

/// 电池优化白名单。
///
/// 后台提醒跑不跑得起来，一半看这个：系统一旦把 App 冻结，WorkManager
/// 之外的东西全停。豁免要用户在系统弹窗里点一次「允许」，代码点不了。
class Power {
  Power._();

  static const _ch = MethodChannel('openbbs/power');

  /// 已经在白名单里。拿不到（网页、iOS、老安卓）就当没有。
  static Future<bool> ignoringBattery() async {
    try {
      return await _ch.invokeMethod<bool>('isIgnoring') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 弹系统那个「是否允许忽略电池优化」。玩家点了才生效，返回值只代表弹窗发出去了。
  static Future<bool> requestIgnore() async {
    try {
      return await _ch.invokeMethod<bool>('requestIgnore') ?? false;
    } catch (_) {
      return false;
    }
  }
}
