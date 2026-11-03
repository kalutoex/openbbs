import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api.dart';
import '../img_cache.dart';
import '../img_size_store.dart';
import '../store.dart';
import '../utils.dart';
import 'name_tag.dart';
import 'user_link.dart';

import '../l10n/error_text.dart';
/// 时间线里的一条帖子。
class ThreadTile extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onTap;
  final VoidCallback? onDeleted;

  const ThreadTile({
    super.key,
    required this.item,
    required this.onTap,
    this.onDeleted,
  });

  Future<void> _delete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删掉这帖？'),
        content: const Text('帖子和下面所有回复一起消失，删了找不回来。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('算了'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删掉'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.delete('/t/${item['id']}');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('帖子已删')));
      onDeleted?.call();
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(errorText(context, e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = AppState.instance;
    return AnimatedBuilder(
      animation: Listenable.merge([st.density, st.thumbs]),
      builder: (context, _) =>
          _build(context, st.density.value, st.thumbs.value),
    );
  }

  Widget _build(BuildContext context, int density, bool thumbs) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final author = (item['author'] ?? '') as String;
    final replies = (item['reply_count'] ?? 0) as int;
    final good = item['is_good'] == true;
    final ts = (item['updated_at'] ?? item['created_at'] ?? 0) as int;

    final label = ((item['forum_title'] ?? item['forum'] ?? '') as String)
        .trim();
    final imgs = ((item['images'] as List?) ?? const []).cast<String>();
    final coverSizes = (item['img_sizes'] as List?) ?? const [];
    final cover = thumbs && imgs.isNotEmpty ? imgs.first : '';

    final excerpt = ((item['excerpt'] ?? '') as String).trim();
    const maxChars = 200;
    final cut = excerpt.runes.length > maxChars;
    final shown = cut
        ? String.fromCharCodes(excerpt.runes.take(maxChars))
        : excerpt;

    final pad = switch (density) {
      0 => 9.0,
      2 => 19.0,
      _ => 14.0,
    };
    final gap = switch (density) {
      0 => 7.0,
      2 => 12.0,
      _ => 10.0,
    };

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, pad, 16, pad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _ForumChip(text: label.isEmpty ? '综合' : label),
                const SizedBox(width: 8),
                if (item['is_top'] == true) ...[
                  Text(
                    '置顶',
                    style: tt.labelSmall?.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                if (good) ...[
                  Text(
                    '精华',
                    style: tt.labelSmall?.copyWith(
                      color: cs.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                if (imgs.length >= 2) ...[
                  Text(
                    '多图片',
                    style: tt.labelSmall?.copyWith(
                      color: cs.tertiary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: NameTag(
                    name: author,
                    handle: '${item['handle'] ?? ''}',
                    onTap: () =>
                        openUserPage(context, '${item['handle'] ?? ''}'),
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  timeAgo(ts),
                  style: tt.labelSmall?.copyWith(color: cs.outline),
                ),
                if (item['can_delete'] == true) ...[
                  const SizedBox(width: 2),
                  InkResponse(
                    onTap: () => _delete(context),
                    radius: 18,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.delete_outline,
                        size: 16,
                        color: cs.outline,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            SizedBox(height: gap),
            Text(
              (item['title'] ?? '') as String,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: tt.titleSmall?.copyWith(
                fontSize: (tt.titleSmall?.fontSize ?? 14) + 3,
                fontWeight: FontWeight.w800,
                height: 1.3,
              ),
            ),
            if (excerpt.isNotEmpty) ...[
              SizedBox(height: (gap * 0.5).clamp(3, 8).toDouble()),
              _excerptText(shown, cut, cs, tt),
            ],
            if (cover.isNotEmpty) ...[
              SizedBox(height: gap),
              Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  // 占位和成品同一个框，图下来不会再从 4:3 跳成别的比例。
                  width: 208,
                  child: AspectRatio(
                    aspectRatio: _coverRatio(cover, coverSizes),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        cacheManager: ImgCache.manager,
                        imageUrl: Api.img(cover),
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                        memCacheWidth: (208 *
                                MediaQuery.devicePixelRatioOf(context))
                            .round()
                            .clamp(208, 640),
                        placeholder: (_, _) => Container(
                          color: cs.surfaceContainerHighest,
                        ),
                        errorWidget: (_, _, _) => Container(
                          color: cs.surfaceContainerHighest,
                          child: Icon(
                            Icons.broken_image_outlined,
                            size: 20,
                            color: cs.outline,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
            SizedBox(height: gap),
            Row(
              children: [
                Icon(Icons.chat_bubble_outline, size: 14, color: cs.outline),
                const SizedBox(width: 5),
                Text(
                  replies == 0 ? '评论' : bigNum(replies),
                  style: tt.labelSmall?.copyWith(color: cs.outline),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 封面比例：服务端给的优先，本地存过的次之，都没有才 4:3。
  /// 重点是加载前后这个框不能变。
  ///
  /// 列表里的封面是缩略图，比正文更紧：超过 0.7（高不到宽的 1.4 倍）就裁，
  /// 只露上半截。点进去还是整张。
  double _coverRatio(String cover, List<dynamic> sizes) {
    double? raw;
    if (sizes.isNotEmpty && sizes.first is List) {
      final v = sizes.first as List;
      if (v.length == 2) {
        final w = (v[0] as num).toDouble();
        final h = (v[1] as num).toDouble();
        if (w > 0 && h > 0) raw = (w / h).clamp(0.2, 5.0);
      }
    }
    raw ??= () {
      final s = ImgSizeStore.get(Api.img(cover));
      if (s == null || s.height <= 0) return null;
      return (s.width / s.height).clamp(0.2, 5.0);
    }();
    if (raw == null) return 4 / 3;
    return raw < _coverMinRatio ? _coverMinRatio : raw;
  }

  static const _coverMinRatio = 0.7;

  /// 正文预览：超过 200 字就用渐变色的省略号收尾，要点进去才看全文。
  Widget _excerptText(String text, bool cut, ColorScheme cs, TextTheme tt) {
    final style = tt.bodyMedium?.copyWith(
      color: cs.onSurfaceVariant,
      height: 1.55,
    );
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: text),
          if (cut)
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (rect) => LinearGradient(
                  colors: [cs.primary, cs.tertiary, cs.secondary],
                ).createShader(rect),
                child: Text(
                  '…',
                  style: style?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
      maxLines: 4,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }
}

class _ForumChip extends StatelessWidget {
  final String text;
  const _ForumChip({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: cs.onSecondaryContainer,
        ),
      ),
    );
  }
}
