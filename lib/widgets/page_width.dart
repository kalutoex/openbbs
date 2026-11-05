import 'package:flutter/material.dart';

/// 宽屏把内容收进中间一栏。
///
/// 手机上（宽度不够）原样返回，不多包一层，也不改任何布局。
/// 网页版、平板、横屏铺满整屏时，一行正文拉过 1400 像素没法读，
/// 帖子列表也会左对齐贴在边上、右边空一片。这里收到 [max] 居中。
class PageWidth extends StatelessWidget {
  final Widget child;
  final double max;

  const PageWidth({super.key, required this.child, this.max = 760});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        if (!c.maxWidth.isFinite || c.maxWidth <= max) return child;
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: max),
            child: child,
          ),
        );
      },
    );
  }
}
