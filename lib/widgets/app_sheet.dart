import 'package:flutter/material.dart';

/// 底部弹窗。
///
/// 宽屏（>=600dp）时收窄居中：默认的底部弹窗会横跨整条屏幕，
/// 在平板和网页上像一条贴底的横带，选项左右散得很开。
/// 窄屏保持原样，什么都不改。
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool showDragHandle = false,
  bool useSafeArea = false,
  bool isDismissible = true,
  bool enableDrag = true,
  Color? backgroundColor,
}) {
  final wide = MediaQuery.sizeOf(context).width >= 600;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    showDragHandle: showDragHandle,
    useSafeArea: useSafeArea,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    backgroundColor: backgroundColor,
    constraints: wide ? const BoxConstraints(maxWidth: 560) : null,
    builder: builder,
  );
}
