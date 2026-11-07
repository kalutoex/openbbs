import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../api.dart';
import '../img_cache.dart';
import '../img_size_store.dart';
import '../save_cover.dart';
import 'retry_image.dart';

import '../l10n/l10n.dart';
import 'toast.dart';

/// 楼层里的图片。1 张大图，多张九宫格。点开全屏。
class PostImages extends StatelessWidget {
  final List<String> urls;

  /// 与 urls 同序的 [宽, 高]，服务端读文件头给的。读不出来是 null。
  final List<dynamic> sizes;

  /// Hero 前缀。同一个帖子里两张一样的图（转发、引用）tag 会撞，
  /// Hero 撞了就抛断言，所以带上楼层号把它们分开。
  final String heroPrefix;

  const PostImages({
    super.key,
    required this.urls,
    this.sizes = const [],
    this.heroPrefix = '',
  });

  String _tag(int i) => '$heroPrefix:${urls[i]}';

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
            child: Hero(
              tag: _tag(0),
              child: SizedBox(
                width: w,
                child: AspectRatio(
                  aspectRatio: ratio,
                  child: RetryImage(
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
            child: Hero(
              tag: _tag(i),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: RetryImage(
                  url: Api.thumb(urls[i], 320),
                  fit: BoxFit.cover,
                  memCacheWidth: cellPx,
                  probeSize: i >= sizes.length || sizes[i] is! List,
                ),
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
        builder: (_) =>
            ImageViewerPage(urls: urls, initial: index, heroPrefix: heroPrefix),
      ),
    );
  }
}

/// 全屏看图：双指缩放、双击放大、左右翻页、右上角下载。
class ImageViewerPage extends StatefulWidget {
  final List<String> urls;
  final int initial;

  /// 与缩略图那侧一致的 Hero 前缀，空串就是不做转场。
  final String heroPrefix;

  const ImageViewerPage({
    super.key,
    required this.urls,
    this.initial = 0,
    this.heroPrefix = '',
  });

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
    try {
      final r = await http
          .get(Uri.parse(Api.img(widget.urls[_i])))
          .timeout(const Duration(seconds: 30));
      if (r.statusCode >= 400) {
        throw Exception('download failed (${r.statusCode})');
      }
      final name = 'openbbs_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final where = await saveImageBytes(r.bodyBytes, name);
      if (!mounted) return;
      toast(context, Lc.current.savedTo(where), floating: true);
    } catch (e) {
      if (!mounted) return;
      toast(context, Lc.current.saveFailed('$e'), floating: true);
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
            itemBuilder: (c, i) {
              final img = _ZoomableImage(
                url: Api.img(widget.urls[i]),
                cacheWidth: _viewerPx,
                onTap: () => Navigator.of(context).pop(),
              );
              // 只给正在看的那一页挂 Hero。
              //
              // 每页都挂的话，PageView 留在树里的邻页也带着 Hero，退出时
              // 两个 Hero 各找一个格子往回飞——看着就是两张图一起退出。
              if (i != _i) return img;
              return Hero(
                tag: '${widget.heroPrefix}:${widget.urls[i]}',
                child: img,
              );
            },
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
