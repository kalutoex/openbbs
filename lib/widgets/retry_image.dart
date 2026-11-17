import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart'
    show ImageRenderMethodForWeb;
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart'
    show HttpExceptionWithStatus;

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

  /// 转圈的颜色。默认跟主题走；黑底的大图查看器里要传白色，
  /// 不然深色主题下那圈几乎看不见。
  final Color? indicatorColor;

  /// 彻底放弃（五次都没成）之后换成什么。传了就用它，不传就还是
  /// 「点击重试」那块灰底。个人主页封面这种宁可退回渐变色也不想要一块灰。
  final Widget? errorPlaceholder;

  const RetryImage({
    super.key,
    required this.url,
    required this.fit,
    this.memCacheWidth,
    this.alignment = Alignment.center,
    this.probeSize = true,
    this.bustCache = false,
    this.placeholderHeight,
    this.indicatorColor,
    this.errorPlaceholder,
  });

  @override
  State<RetryImage> createState() => RetryImageState();
}

class RetryImageState extends State<RetryImage> {
  int _round = 0;

  /// 自动重试的节奏。头两下贴着走：坏的多半是本地缓存里那张，
  /// 换掉就能出；后面拉开间隔，给慢网把包收完的时间。
  /// 五下加起来约 3.5 秒，不成就露「点击重试」。
  static const _autoDelays = <Duration>[
    Duration(milliseconds: 100),
    Duration(milliseconds: 100),
    Duration(milliseconds: 400),
    Duration(milliseconds: 900),
    Duration(seconds: 2),
  ];

  int _auto = 0; // 已经自动试过几次
  bool _gaveUp = false; // 五下都白搭，交给用户点
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.probeSize) unawaited(_remember());
  }

  @override
  void didUpdateWidget(covariant RetryImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 列表把这一格拿去显示下一张图了，重试次数得从头算。
    if (oldWidget.url != widget.url) {
      _timer?.cancel();
      _auto = 0;
      _gaveUp = false;
      _round = 0;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
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

  /// 图挂了。先自己悄悄试几下，试满了才把「点击重试」摆出来。
  void _onError(Object e) {
    if (!mounted) return;
    // 404/403 这类再试也没用，别白烧五次。
    if (e is HttpExceptionWithStatus &&
        e.statusCode >= 400 &&
        e.statusCode < 500) {
      if (!_gaveUp) setState(() => _gaveUp = true);
      return;
    }
    if (_auto >= _autoDelays.length) {
      if (!_gaveUp) setState(() => _gaveUp = true);
      return;
    }
    // 一屏几十张一起挂的时候别同时打过去，按格子错开几十毫秒。
    final jitter = Duration(milliseconds: (hashCode % 7) * 20);
    final wait = _autoDelays[_auto++] + jitter;
    _timer?.cancel();
    _timer = Timer(wait, () async {
      if (!mounted) return;
      await ImgCache.evict(_url);
      if (mounted) setState(() => _round++);
    });
  }

  Future<void> _retry() async {
    _timer?.cancel();
    _auto = 0;
    _gaveUp = false;
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
      errorListener: _onError,
      placeholder: (_, _) =>
          _box(cs, loading: true, h: widget.placeholderHeight),
      // 还在自动重试的时候继续转圈，别让用户以为已经放弃了。
      errorWidget: (_, _, _) {
        if (!_gaveUp) {
          return _box(cs, loading: true, h: widget.placeholderHeight);
        }
        if (widget.errorPlaceholder != null) return widget.errorPlaceholder!;
        return GestureDetector(
          onTap: _retry,
          behavior: HitTestBehavior.opaque,
          child: _box(cs, loading: false),
        );
      },
    );
  }

  /// 占位框。loading 时才按 placeholderHeight 撑高度——
  /// 图回来了得按它自己的比例走，固定高度会把条漫长图压扁。
  Widget _box(ColorScheme cs, {required bool loading, double? h}) => Container(
    height: loading ? h : null,
    color: cs.surfaceContainerHighest,
    alignment: Alignment.center,
    child: loading
        ? SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: widget.indicatorColor,
            ),
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
