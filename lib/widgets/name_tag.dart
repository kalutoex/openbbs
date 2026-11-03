import 'package:flutter/material.dart';

/// 名字后面跟一个灰色的 @标识，像推特那样：
/// **昵称**  @handle
/// handle 为空就只显示名字，不留多余的空格。
class NameTag extends StatelessWidget {
  const NameTag({
    super.key,
    required this.name,
    this.handle = '',
    this.style,
    this.maxLines = 1,
    this.onTap,
  });

  final String name;
  final String handle;
  final TextStyle? style;
  final int maxLines;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = style ?? Theme.of(context).textTheme.titleSmall!;
    final h = handle.trim().replaceFirst(RegExp(r'^@'), '');
    final text = Text.rich(
      TextSpan(
        children: [
          TextSpan(text: name, style: base),
          if (h.isNotEmpty)
            TextSpan(
              text: '  @$h',
              style: TextStyle(
                fontSize: (base.fontSize ?? 14) - 2,
                fontWeight: FontWeight.w400,
                color: cs.outline,
              ),
            ),
        ],
      ),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
    if (onTap == null) return text;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: text,
    );
  }
}
