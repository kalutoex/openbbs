import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart'
    show ImageRenderMethodForWeb;
import 'package:flutter/material.dart';

import '../user_hue.dart';
import '../api.dart';
import '../img_cache.dart';
import '../img_size_store.dart';
import '../store.dart';
import '../utils.dart';
import 'avatar.dart';
import 'file_card.dart';
import 'live_time.dart';
import 'post_images.dart';

import 'user_link.dart';

import '../l10n/error_text.dart';
import '../l10n/l10n.dart';
import '../ui_config.dart';
import 'toast.dart';

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
        title: Text(Lc.current.deletePostConfirm),
        content: Text(Lc.current.deleteThreadConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(Lc.current.forgetIt),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(Lc.current.deleteIt),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.delete('/t/${item['id']}');
      if (!context.mounted) return;
      toast(context, Lc.current.postDeleted);
      onDeleted?.call();
    } on ApiException catch (e) {
      if (!context.mounted) return;
      toast(context, errorText(context, e));
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
    final handle = (item['handle'] ?? '') as String;
    final replies = (item['reply_count'] ?? 0) as int;
    final good = item['is_good'] == true;
    final ts = (item['updated_at'] ?? item['created_at'] ?? 0) as int;

    final imgs = ((item['images'] as List?) ?? const []).cast<String>();
    final files = PostFile.listOf(item['files']);
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

    final radius = BorderRadius.circular(16);

    return Padding(
      // 卡片之间靠这条外边距隔开，列表的分割线已经不用了。
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Material(
        // 谁发的帖子就是谁的色（设置里可关，关了就回默认底）。
        color:
            hueCardTint(
              hueOfUser(item),
              Theme.of(context).brightness == Brightness.dark,
            ) ??
            cs.surfaceContainerLow,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: cs.outlineVariant.withValues(
                  alpha: Theme.of(context).brightness == Brightness.light
                      ? .55
                      : .35,
                ),
              ),
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(14, pad, 14, pad),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      CircleAvatarImg(
                        url: '${item['avatar'] ?? ''}',
                        name: author,
                        radius: UiConfig.px('threadCard.avatarRadius'),
                        hue: hueOfUser(item),
                      ),
                      SizedBox(width: UiConfig.px('threadCard.gap')),
                      // 昵称在上、@账号在下，两行整体对着头像居中；
                      // 角标和时间跟着昵称那一行走，不跟两行块居中。
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () => openUserPage(context, handle),
                                    child: Text(
                                      author,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: tt.bodyMedium?.copyWith(
                                        fontSize:
                                            (tt.bodyMedium?.fontSize ?? 14) + 1,
                                        fontWeight: FontWeight.w600,
                                        height: 1.2,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // 角标相对时间的位置由后台配：默认排在时间左边，
                                // 从右往左越靠前越贴近时间。也能换成右侧或另起一行。
                                _tail(
                                  tt,
                                  cs,
                                  [
                                    if (imgs.length >= 2)
                                      _tag(Lc.current.multiImage, cs.tertiary),
                                    if (good)
                                      _tag(Lc.current.featured, cs.error),
                                    if (item['is_top'] == true)
                                      _tag(Lc.current.pinned, cs.primary),
                                  ],
                                  LiveTime(
                                    ts,
                                    style: tt.labelSmall?.copyWith(
                                      color: cs.outline,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (handle.trim().isNotEmpty)
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => openUserPage(context, handle),
                                child: Text(
                                  '@${handle.trim().replaceFirst(RegExp(r'^@'), '')}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: tt.bodySmall?.copyWith(
                                    fontSize:
                                        (tt.bodySmall?.fontSize ?? 12) + 1,
                                    color: cs.outline,
                                    height: 1.2,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
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
                    // 封面宽度跟着卡片走，上限 [_coverMaxWidth]。
                    // 以前死写 208，宽屏上就是一张贴纸，撑不起卡片的份量。
                    LayoutBuilder(
                      builder: (ctx, box) {
                        final w = box.maxWidth < _coverMaxWidth
                            ? box.maxWidth
                            : _coverMaxWidth;
                        return Align(
                          alignment: Alignment.centerLeft,
                          child: SizedBox(
                            // 占位和成品同一个框，图下来不会再从 4:3 跳成别的比例。
                            width: w,
                            child: AspectRatio(
                              aspectRatio: _coverRatio(cover, coverSizes),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                // 封面自己接点击：卡片整体是进帖子，图这一块
                                // 直接开全屏查看器，多图进去还能左右翻。
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => _openImages(context, imgs),
                                  child: Hero(
                                    tag: 't${item['id']}:$cover',
                                    child: CachedNetworkImage(
                                      cacheManager: ImgCache.manager,
                                      imageRenderMethodForWeb:
                                          ImageRenderMethodForWeb.HttpGet,
                                      imageUrl: Api.thumb(cover, 320),
                                      fit: BoxFit.cover,
                                      alignment: Alignment.topCenter,
                                      memCacheWidth:
                                          (w *
                                                  MediaQuery.devicePixelRatioOf(
                                                    ctx,
                                                  ))
                                              .round()
                                              .clamp(208, 720),
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
                          ),
                        );
                      },
                    ),
                  ],
                  if (files.isNotEmpty) CompactFiles(files: files),
                  SizedBox(height: gap),
                  Row(
                    children: [
                      Icon(
                        Icons.chat_bubble_outline,
                        size: 14,
                        color: cs.outline,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        replies == 0 ? Lc.current.comments : bigNum(replies),
                        style: tt.labelSmall?.copyWith(color: cs.outline),
                      ),
                      // 删除放右下：跟评论数同一行，手够得着，也不挨着头像。
                      const Spacer(),
                      if (item['can_delete'] == true)
                        InkResponse(
                          onTap: () => _delete(context),
                          radius: 16,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(6, 2, 0, 2),
                            child: Icon(
                              Icons.delete_outline,
                              size: 17,
                              color: cs.outline,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 置顶 / 精华 / 多图。三个彩色字挤在一起太碎，做成小胶囊。
  /// 时间加角标那一块。角标在左、在右、另起一行三种，后台一句话就换。
  Widget _tail(TextTheme tt, ColorScheme cs, List<Widget> tags, Widget time) {
    final side = UiConfig.str('threadCard.tagSide');
    if (tags.isEmpty) return time;
    Widget spaced() => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < tags.length; i++) ...[
          if (i > 0) const SizedBox(width: 5),
          tags[i],
        ],
      ],
    );
    if (side == 'belowTime') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [time, const SizedBox(height: 5), spaced()],
      );
    }
    if (side == 'rightOfTime') {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [time, const SizedBox(width: 5), spaced()],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [spaced(), const SizedBox(width: 5), time],
    );
  }

  Widget _tag(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 10.5,
        height: 1.2,
        fontWeight: FontWeight.w700,
        color: color,
      ),
    ),
  );

  /// 封面比例：服务端给的优先，本地存过的次之，都没有才 4:3。
  /// 重点是加载前后这个框不能变。
  ///
  /// 列表里的封面是缩略图，比正文更紧：超过 0.7（高不到宽的 1.4 倍）就裁，
  /// 只露上半截。点进去还是整张。
  /// 封面上点一下：直接进全屏查看器，多图可以左右翻。整张卡片还是进帖子。
  void _openImages(BuildContext context, List<String> imgs) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ImageViewerPage(
          urls: imgs,
          initial: 0,
          heroPrefix: 't${item['id']}',
        ),
      ),
    );
  }

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

  /// 封面最大宽度：再宽就成海报了，列表里一屏看不下几条。
  static const _coverMaxWidth = 280.0;

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
