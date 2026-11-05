import 'package:flutter/material.dart';

/// 全站统一的卡片外壳。
///
/// 圆角 16、淡描边、surfaceContainerLow 底，带 onTap 时自动上水波纹。
/// 列表、详情、我的、站点都用它，别再各写各的 BoxDecoration——
/// 改一次圆角要改五个文件的日子过够了。
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final Color? borderColor;
  final VoidCallback? onTap;

  /// 指定宽度。放在 crossAxisAlignment.start 的 Column 里时，
  /// 卡片默认会缩成内容那么宽，这里给个撑满的开关。
  final double? width;

  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.color,
    this.borderColor,
    this.onTap,
    this.width,
  });

  /// 卡片描边色：浅色下略重一点，深色下要淡，不然一圈白线很扎眼。
  static BorderSide sideOf(BuildContext context, {Color? override}) {
    final cs = Theme.of(context).colorScheme;
    return BorderSide(
      color:
          override ??
          cs.outlineVariant.withValues(
            alpha: Theme.of(context).brightness == Brightness.light ? .55 : .35,
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(16);
    final bg = color ?? cs.surfaceContainerLow;
    final border = borderColor == null ? sideOf(context).color : borderColor!;

    final inner = padding == null
        ? child
        : Padding(padding: padding!, child: child);

    // 底色和圆角交给 Material：卡片里常放 ListTile，它只在最近的 Material 上
    // 画背景和波纹，外面套个带色的 Container 会被 debug 断言抓出来。
    final body = Material(
      color: bg,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? inner
          : InkWell(borderRadius: radius, onTap: onTap, child: inner),
    );

    return Container(
      margin: margin,
      width: width,
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: border),
      ),
      child: body,
    );
  }
}
