import 'package:flutter/services.dart';

/// 上传期间让进程活着。
///
/// 安卓一退到后台就喜欢冻进程，上传跟着断。这里挂一个前台服务，
/// 只在传东西的时候有，传完就撤，不常驻。
///
/// 别的平台（网页、桌面）没有这一套，调了也只是空跑。
const _ch = MethodChannel('openbbs/keepalive');

bool _on = false;

Future<void> keepAliveStart(String title, String text) async {
  try {
    await _ch.invokeMethod('start', {'title': title, 'text': text});
    _on = true;
  } catch (_) {
    // 网页、桌面上没有这个通道，安静跳过
  }
}

Future<void> keepAliveUpdate(String title, String text) async {
  if (!_on) return;
  try {
    await _ch.invokeMethod('update', {'title': title, 'text': text});
  } catch (_) {}
}

Future<void> keepAliveStop() async {
  if (!_on) return;
  _on = false;
  try {
    await _ch.invokeMethod('stop');
  } catch (_) {}
}
