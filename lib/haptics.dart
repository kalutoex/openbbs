import 'package:flutter/services.dart';

/// 触感反馈。
///
/// 安卓上原来一点反馈都没有，点、按、发出去全是干的，隔着一层玻璃。
/// 只留四档，别到处自己定力度——同一件事在不同页面震得不一样，反而更怪。
/// 网页版和部分机型没有振动马达，调了也是空操作，不用做平台判断。
class Haptics {
  Haptics._();

  /// 轻点：切 tab、开关、选中
  static void tap() {
    HapticFeedback.selectionClick();
  }

  /// 办成一件事：发送、保存、点赞
  static void done() {
    HapticFeedback.lightImpact();
  }

  /// 按住：长按菜单、开始拖拽
  static void press() {
    HapticFeedback.mediumImpact();
  }

  /// 出岔子：操作失败、删掉东西
  static void warn() {
    HapticFeedback.heavyImpact();
  }
}
