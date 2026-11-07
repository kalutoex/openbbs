import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

/// 系统分享。安卓/iOS 弹系统面板，网页走 navigator.share，桌面走系统对话框。
///
/// 只分享文字，不碰文件——图片要分享得先落临时文件，网页上根本没这回事，
/// 真需要的时候再说。
Future<bool> shareText(String text, {String? subject}) async {
  if (text.trim().isEmpty) return false;
  try {
    // 网页版需要用户手势里同步调用，这里没有 await 前置操作，safe。
    await SharePlus.instance.share(ShareParams(text: text, subject: subject));
    return true;
  } catch (e) {
    // 用户按了取消不算失败，但各家抛的异常不一样，统一吞掉。
    debugPrint('share failed: $e');
    return false;
  }
}
