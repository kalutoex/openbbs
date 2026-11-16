import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart'
    show ImageRenderMethodForWeb;
import 'package:flutter/material.dart';

import '../img_cache.dart';
import '../img_size_store.dart';

import '../l10n/l10n.dart';

/// 加载失败能点一下重来的图。网络差的时候不用退出去重进。
class RetryImage extends StatefulWidget {
  final String url;
  final int? memCacheWidth;
  final BoxFit fit;
  final Alignment alignment;

  /// 要不要单独解一次图把真实宽高存下来。服务端已经给了尺寸就不做，
  /// 网页版上那次多在 iOS 上是白占一份显存。
  final bool probeSize;

  /// 点一下重试时，往后端要一张新的（/sources/img 会跳过自己的缓存）。
  /// 书源那边的图是经过服务端转的，服务端存了一张坏的，光清本地缓存没用。
  final bool bustCache;

  /// 加载中占多高。纵向看漫画时一张图撑满宽度、高度未知，
  /// 给它一个占位高度，图回来之前列表不会缩成一条。
  final double? placeholderHeight;

  const RetryImage({
    super.key,
    required this.url,
    required this.fit,
    this.memCacheWidth,
    this.alignment = Alignment.center,
    this.probeSize = true,
    this.bustCache = false,
    this.placeholderHeight,
  });

  @override
  State<RetryImage> createState() => RetryImageState();
}

class RetryImageState extends State<RetryImage> {
  int _round = 0;

  @override
  void initState() {
    super.initState();
    if (widget.probeSize) unawaited(_remember());
  }

  /// 解码一次拿到真实宽高存起来，下次这个帖子再滑到就不用猜比例了。
  Future<void> _remember() async {
    if (ImgSizeStore.get(widget.url) != null) return;
    try {
      final provider = CachedNetworkImageProvider(
        widget.url,
        cacheManager: ImgCache.manager,
        maxWidth: widget.memCacheWidth,
        imageRenderMethodForWeb: ImageRenderMethodForWeb.HttpGet,
      );
      final stream = provider.resolve(ImageConfiguration.empty);
      late final ImageStreamListener listener;
      final done = Completer<void>();
      void finish() {
        stream.removeListener(listener);
        if (!done.isCompleted) done.complete();
      }

      listener = ImageStreamListener((info, _) {
        unawaited(
          ImgSizeStore.put(
            widget.url,
            Size(info.image.width.toDouble(), info.image.height.toDouble()),
          ),
        );
        finish();
      }, onError: (_, _) => finish());
      stream.addListener(listener);
    } catch (_) {
      // 探测失败就继续用默认比例，不影响显示。
    }
  }

  /// 第几轮重试之后的地址。bustCache 打开时给 URL 挂个 f 参数，
  /// 后端据此跳过自己的磁盘缓存，重新问一次源站。
  String get _url {
    if (!widget.bustCache || _round == 0) return widget.url;
    final sep = widget.url.contains('?') ? '&' : '?';
    return '${widget.url}${sep}f=$_round';
  }

  Future<void> _retry() async {
    await ImgCache.evict(_url);
    if (mounted) setState(() => _round++);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return CachedNetworkImage(
      cacheManager: ImgCache.manager,
      // 网页版默认用 <img> 元素取图，memCacheWidth 会被忽略，图按原尺寸解码。
      // 一张 1200×1600 解码就是 7MB，几十张就把图片缓存顶穿，于是滑回去又要重下，
      // 反复几次浏览器那边就再也画不出来。改成走 http 取字节，才能按显示尺寸解码。
      imageRenderMethodForWeb: ImageRenderMethodForWeb.HttpGet,
      key: ValueKey('${widget.url}#$_round'),
      fadeInDuration: const Duration(milliseconds: 180),
      imageUrl: _url,
      memCacheWidth: widget.memCacheWidth,
      fit: widget.fit,
      alignment: widget.alignment,
      placeholder: (_, _) =>
          _box(cs, loading: true, h: widget.placeholderHeight),
      errorWidget: (_, _, _) => GestureDetector(
        onTap: _retry,
        behavior: HitTestBehavior.opaque,
        child: _box(cs, loading: false),
      ),
    );
  }

  /// 占位框。loading 时才按 placeholderHeight 撑高度——
  /// 图回来了得按它自己的比例走，固定高度会把条漫长图压扁。
  Widget _box(ColorScheme cs, {required bool loading, double? h}) => Container(
    height: loading ? h : null,
    color: cs.surfaceContainerHighest,
    alignment: Alignment.center,
    child: loading
        ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 1.5),
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.refresh, size: 18, color: cs.outline),
              const SizedBox(height: 2),
              Text(
                Lc.current.tapToRetry,
                style: TextStyle(fontSize: 10, color: cs.outline),
              ),
            ],
          ),
  );
}
