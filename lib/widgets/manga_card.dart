import 'package:flutter/material.dart';

import 'retry_image.dart';

/// 一本书的格子：封面 + 书名 + 底下一行小字。
///
/// 书架、榜单共用这一种：同一个人在两处翻书，封面大小、圆角、字号
/// 一变就会觉得「换了个 App」。差别只有右下那行字（进度 / 最新章节）
/// 和有没有红点。
class MangaCoverCard extends StatelessWidget {
  final String title;

  /// 底下那行小字。空串就不占位置。
  final String sub;

  /// 小字用主色（有阅读进度时用它，比灰色显眼但不算警告）。
  final bool highlight;

  final String coverUrl;
  final VoidCallback onTap;

  /// 长按。书架用它进多选（批量下载、标已读、删离线）。
  final VoidCallback? onLongPress;

  /// 左下角那个小标：离线下到第几话、或者正在下多少。
  final String badge;

  /// 正在下的进度（0..1）。空着就不画那根条。
  final double? progress;

  /// 被勾上了（多选模式）。
  final bool selected;

  /// 换封面纹理用。CanvasKit 会把不在屏幕上的图回收，
  /// 而 ImageCache 还记着「已解码」，回来就是一整块黑。
  final String imageKey;
  final bool bustCache;

  /// 右上角那个红点：这本有新话没看。
  final bool hasNew;

  /// 封面请求宽度。格子小就别按原图解码，省内存。
  final int memWidth;

  const MangaCoverCard({
    super.key,
    required this.title,
    this.sub = '',
    this.highlight = false,
    required this.coverUrl,
    required this.onTap,
    this.onLongPress,
    this.badge = '',
    this.progress,
    this.selected = false,
    this.imageKey = '',
    this.bustCache = false,
    this.hasNew = false,
    this.memWidth = 320,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: coverUrl.isEmpty
                        ? Container(
                            color: cs.surfaceContainerHighest,
                            child: Icon(Icons.menu_book, color: cs.outline),
                          )
                        : RetryImage(
                            key: imageKey.isEmpty
                                ? null
                                : ValueKey('$coverUrl#$imageKey'),
                            url: coverUrl,
                            fit: BoxFit.cover,
                            memCacheWidth: memWidth,
                            probeSize: false,
                            bustCache: bustCache,
                          ),
                  ),
                ),
                if (badge.isNotEmpty)
                  Positioned(
                    left: 4,
                    top: 4,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: .92),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        badge,
                        style: TextStyle(
                          fontSize: 9.5,
                          height: 1.1,
                          color: cs.onPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                if (progress != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(10),
                      ),
                      child: LinearProgressIndicator(
                        value: progress! <= 0 ? null : progress,
                        minHeight: 3,
                      ),
                    ),
                  ),
                if (selected)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: .22),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: cs.primary, width: 2),
                      ),
                      child: Align(
                        alignment: Alignment.topRight,
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(Icons.check_circle,
                              size: 18, color: cs.primary),
                        ),
                      ),
                    ),
                  ),
                if (hasNew)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: cs.error,
                        shape: BoxShape.circle,
                        border: Border.all(color: cs.surface, width: 1.2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (sub.isNotEmpty)
            Text(
              sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tt.labelSmall?.copyWith(
                color: highlight ? cs.primary : cs.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}
