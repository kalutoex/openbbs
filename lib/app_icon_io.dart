import 'package:flutter/services.dart';

/// 安卓/桌面端：走 MainActivity 里的 openbbs/icon 通道。
const bool supported = true;

const _ch = MethodChannel('openbbs/icon');

Future<String> currentAppIcon() async {
  try {
    final v = await _ch.invokeMethod<String>('current');
    return v ?? 'mint';
  } catch (_) {
    // Windows 上没有这个通道；查不到就按默认图标算，不影响别的。
    return 'mint';
  }
}

Future<void> setAppIcon(String key) async {
  try {
    await _ch.invokeMethod<bool>('set', {'key': key});
  } on MissingPluginException {
    throw UnsupportedError('这个平台换不了图标');
  }
}
