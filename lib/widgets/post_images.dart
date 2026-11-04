import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart'
    show ImageRenderMethodForWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../api.dart';
import '../img_cache.dart';
import '../img_size_store.dart';
import '../save_cover.dart';

import '../l10n/l10n.dart';
/// 楼层里的图片。1 张大图，多张九宫格。点开全屏。
class PostImages extends StatelessWidget {
  final List<String> urls;

  /// 与 urls 同序的 [宽, 高]，服务端读文件头给的。读不出来是 null。
  final List<dynamic> sizes;

  const PostImages({super.key, required this.urls, this.sizes = const []});

  /// 竖图底线：高超过宽的 2.2 倍（也就是比例低于 0.45）才裁，裁到这条线为止。
  /// 站里现存最竖的一张正好 0.45，所以目前一张都没被裁。
  static const _minRatio = 0.45;

  /// 真实比例。服务端有就用服务端的，没有就看本地存过的，再没有才认 4:3。
  double? _ratioAt(int i) {
    if (i < sizes.length) {
      final v = sizes[i];
      if (v is List && v.length == 2) {
        final w = (v[0] as num).toDouble();
        final h = (v[1] as num).toDouble();
        if (w > 0 && h > 0) return (w / h).clamp(0.2, 5.0);
      }
    }
    final known = ImgSizeStore.get(Api.img(urls[i]));
    if (known != null && known.height > 0) {
      return (known.width / known.height).clamp(0.2, 5.0);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) return const SizedBox.shrink();

    // 图片一律按显示尺寸解码，别把原图整张塞进 image cache。
    final dpr = MediaQuery.devicePixelRatioOf(context);
    if (urls.length == 1) {
      final px = (320 * dpr).round().clamp(320, 1080);
      // 单图最宽显示 320 逻辑像素，给到 720 宽足够 retina 用。
      final url = Api.thumb(urls.first, 720);
      // 比例来自服务端的文件头，加载前就把位置留准：不裁、不跳。
      // 只有比现存最竖的图还长的（真实截图那种）才裁，裁掉的部分点开能看全。
      final raw = _ratioAt(0) ?? 4 / 3;
      final clipped = raw < _minRatio;
      final ratio = clipped ? _minRatio : raw;
      final w = math.min(320.0, MediaQuery.sizeOf(context).width - 48);
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: GestureDetector(
            onTap: () => _open(context, 0),
            child: SizedBox(
              width: w,
              child: AspectRatio(
                aspectRatio: ratio,
                child: _RetryImage(
                  url: url,
                  memCacheWidth: px,
                  fit: BoxFit.cover,
                  // 服务端给了宽高就不用再解一次图去探比例。
                  probeSize: sizes.isEmpty || sizes.first is! List,
                  // 长图裁的时候留上面那截，内容从头开始才对。
                  alignment: clipped ? Alignment.topCenter : Alignment.center,
                ),
              ),
            ),
          ),
        ),
      );
    }

    final n = urls.length;
    final cols = n == 2 ? 2 : 3;
    final cellPx = (104 * dpr).round().clamp(104, 400);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SizedBox(
        width: n == 2 ? 208 : 312,
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: n,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: 4,
            mainAxisSpacing: 4,
          ),
          itemBuilder: (c, i) => GestureDetector(
            onTap: () => _open(context, i),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: _RetryImage(
                url: Api.thumb(urls[i], 320),
                fit: BoxFit.cover,
                memCacheWidth: cellPx,
                probeSize: i >= sizes.length || sizes[i] is! List,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _open(BuildContext context, int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ImageViewerPage(urls: urls, initial: index),
      ),
    );
  }
}

/// 加载失败能点一下重来的图。网络差的时候不用退出去重进。
class _RetryImage extends StatefulWidget {
  final String url;
  final int? memCacheWidth;
  final BoxFit fit;
  final Alignment alignment;

  /// 要不要单独解一次图把真实宽高存下来。服务端已经给了尺寸就不做，
  /// 网页版上那次多在 iOS 上是白占一份显存。
  final bool probeSize;

  const _RetryImage({
    required this.url,
    required this.fit,
    this.memCacheWidth,
    this.alignment = Alignment.center,
    this.probeSize = true,
  });

  @override
  State<_RetryImage> createState() => _RetryImageState();
}

class _RetryImageState extends State<_RetryImage> {
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

      listener = ImageStreamListener(
        (info, _) {
          unawaited(
            ImgSizeStore.put(
              widget.url,
              Size(info.image.width.toDouble(), info.image.height.toDouble()),
            ),
          );
          finish();
        },
        onError: (_, _) => finish(),
      );
      stream.addListener(listener);
    } catch (_) {
      // 探测失败就继续用默认比例，不影响显示。
    }
  }

  Future<void> _retry() async {
    await ImgCache.evict(widget.url);
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
      imageUrl: widget.url,
      memCacheWidth: widget.memCacheWidth,
      fit: widget.fit,
      alignment: widget.alignment,
      placeholder: (_, _) => _box(cs, loading: true),
      errorWidget: (_, _, _) => GestureDetector(
        onTap: _retry,
        behavior: HitTestBehavior.opaque,
        child: _box(cs, loading: false),
      ),
    );
  }

  Widget _box(ColorScheme cs, {required bool loading}) => Container(
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

/// 全屏看图：双指缩放、双击放大、左右翻页、右上角下载。
class ImageViewerPage extends StatefulWidget {
  final List<String> urls;
  final int initial;

  const ImageViewerPage({super.key, required this.urls, this.initial = 0});

  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage> {
  late final PageController _pc = PageController(initialPage: widget.initial);
  late int _i = widget.initial;
  bool _saving = false;

  /// 存当前这一张。按钮触发，不再走长按。
  Future<void> _save() async {
    if (_saving || widget.urls.isEmpty) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final r = await http
          .get(Uri.parse(Api.img(widget.urls[_i])))
          .timeout(const Duration(seconds: 30));
      if (r.statusCode >= 400) {
        throw Exception('download failed (${r.statusCode})');
      }
      final name = 'openbbs_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final where = await saveImageBytes(r.bodyBytes, name);
      messenger.showSnackBar(
        SnackBar(
          content: Text(Lc.current.savedTo('${where}')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(Lc.current.saveFailed('$e')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  int get _viewerPx {
    final mq = MediaQuery.maybeOf(context);
    if (mq == null) return 1200;
    return (mq.size.width * mq.devicePixelRatio * 2).round().clamp(720, 2400);
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pc,
            itemCount: widget.urls.length,
            onPageChanged: (i) => setState(() => _i = i),
            itemBuilder: (c, i) => _ZoomableImage(
              url: Api.img(widget.urls[i]),
              cacheWidth: _viewerPx,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
          if (widget.urls.length > 1)
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_i + 1} / ${widget.urls.length}',
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ),
              ),
            ),
          if (_saving)
            const Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  color: Colors.white70,
                  strokeWidth: 2,
                ),
              ),
            ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 4,
            right: 8,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.download, color: Colors.white70),
                  tooltip: Lc.current.downloadImage,
                  onPressed: _saving ? null : _save,
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 单张图：点一下退出，双击放大/还原。
class _ZoomableImage extends StatefulWidget {
  final String url;
  final int cacheWidth;
  final VoidCallback onTap;

  const _ZoomableImage({
    required this.url,
    required this.cacheWidth,
    required this.onTap,
  });

  @override
  State<_ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<_ZoomableImage> {
  final TransformationController _tc = TransformationController();
  Offset _lastTap = Offset.zero;

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  /// 双击：已放大就还原，否则以点到的位置为中心放大 2.5 倍。
  void _toggleZoom() {
    if (_tc.value.getMaxScaleOnAxis() > 1.2) {
      _tc.value = Matrix4.identity();
      return;
    }
    const s = 2.5;
    final p = _lastTap;
    _tc.value = Matrix4.identity()
      ..translateByDouble(-p.dx * (s - 1), -p.dy * (s - 1), 0, 1)
      ..scaleByDouble(s, s, 1, 1);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onDoubleTapDown: (d) => _lastTap = d.localPosition,
      onDoubleTap: _toggleZoom,
      child: Stack(
        children: [
          InteractiveViewer(
            transformationController: _tc,
            minScale: 1,
            maxScale: 4,
            child: Center(
              child: CachedNetworkImage(
                cacheManager: ImgCache.manager,
                fadeInDuration: const Duration(milliseconds: 180),
                imageUrl: widget.url,
                fit: BoxFit.contain,
                memCacheWidth: widget.cacheWidth,
                placeholder: (_, _) => const Center(
                  child: CircularProgressIndicator(color: Colors.white54),
                ),
                errorWidget: (_, _, _) => const Icon(
                  Icons.broken_image_outlined,
                  color: Colors.white38,
                  size: 40,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
