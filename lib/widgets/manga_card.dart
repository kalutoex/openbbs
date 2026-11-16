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
