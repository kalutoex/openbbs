import 'package:flutter/material.dart';

/// 空列表 / 加载失败时的整页提示。
///
/// 以前各页面各写一段 Center(child: Text(...))，字号颜色都不一样，
/// 出现在屏幕上就是一行孤零零的灰字。统一成一个图标 + 标题 + 说明，
/// 需要的话再给个按钮。
class EmptyView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? hint;
  final Widget? action;

  /// 失败态：图标和标题走错误色。
  final bool error;

  const EmptyView({
    super.key,
    required this.icon,
    required this.title,
    this.hint,
    this.action,
    this.error = false,
  });

  /// 包一层可滚动，套在 RefreshIndicator 里也能下拉。
  Widget scrollable() => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    children: [this],
  );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tint = error ? cs.error : cs.primary;
    final ink = error ? cs.error : cs.onSurface;
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 72, 32, 72),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: .10),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 32, color: tint),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: ink,
              ),
            ),
            if (hint != null) ...[
              const SizedBox(height: 8),
              Text(
                hint!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}
