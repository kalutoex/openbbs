import 'package:flutter/material.dart';

/// 名字下面挂一行灰色的 @标识，像推特那样：
/// **昵称**
/// @handle
/// handle 为空就只显示名字，不多留一行空位。
class NameTag extends StatelessWidget {
  const NameTag({
    super.key,
    required this.name,
    this.handle = '',
    this.style,
    this.maxLines = 1,
    this.onTap,
    this.trailing,
  });

  final String name;
  final String handle;
  final TextStyle? style;
  final int maxLines;
  final VoidCallback? onTap;

  /// 跟在名字右边的小块（等级徽章之类）。挂在名字这一行里，
  /// 否则 handle 比名字宽的时候会被推到 handle 右边缘去。
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = style ?? Theme.of(context).textTheme.titleSmall!;
    final h = handle.trim().replaceFirst(RegExp(r'^@'), '');
    final col = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                name,
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
                style: base,
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 6), trailing!],
          ],
        ),
        if (h.isNotEmpty)
          Text(
            '@$h',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: (base.fontSize ?? 14) - 2,
              fontWeight: FontWeight.w400,
              color: cs.outline,
              height: 1.25,
            ),
          ),
      ],
    );
    if (onTap == null) return col;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: col,
    );
  }
}
