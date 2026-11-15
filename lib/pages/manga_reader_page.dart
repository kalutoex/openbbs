import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../manga.dart';

import '../l10n/l10n.dart';
/// 看漫画。
///
/// 两种读法：横向翻页（单页，双击放大）和纵向连续（条漫、长页）。
/// 位置按书存，退出再进来接着上次那一话那一页。
class MangaReaderPage extends StatefulWidget {
  final MangaDetail detail;
  final int index;

  const MangaReaderPage({
    super.key,
    required this.detail,
    required this.index,
  });

  @override
  State<MangaReaderPage> createState() => _MangaReaderPageState();
}

class _MangaReaderPageState extends State<MangaReaderPage> {
  List<String> _pages = const [];
  late int _ci = widget.index;
  int _page = 0;
  bool _loading = true;
  String? _err;
  bool _chrome = true;
  bool _vertical = false;

  PageController? _pc;
  final _tv = TransformationController();
  double _zoom = 1;

  /// 字号级别的细节不重要，这里只关心「读到哪」。
  String get _posKey => 'manga_pos_${widget.detail.dir}';

  List<MangaChapter> get _chs => widget.detail.chapters;

  @override
  void initState() {
    super.initState();
    _pc = PageController();
    _load(_ci, resume: true);
  }

  @override
  void dispose() {
    _pc?.dispose();
    _tv.dispose();
    super.dispose();
  }

  Future<void> _load(int ci, {bool resume = false}) async {
    if (ci < 0 || ci >= _chs.length) return;
    setState(() {
      _loading = true;
      _err = null;
      _ci = ci;
    });
    try {
      final ch = _chs[ci];
      final pages = await MangaApi.pages(widget.detail.dir, ch.dir);
      if (!mounted) return;
      setState(() {
        _pages = pages;
        _loading = false;
        _page = 0;
      });
      if (_pc != null && _pc!.hasClients) _pc!.jumpToPage(0);
      if (resume) await _restore();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _err = '$e';
      });
    }
  }

  /// 上次读到第几话第几页。只有第一次进来才用得上。
  Future<void> _restore() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_posKey);
      if (raw == null || !mounted) return;
      final parts = raw.split('|');
      if (parts.length != 2) return;
      final chDir = parts[0];
      final page = int.tryParse(parts[1]) ?? 0;
      final i = _chs.indexWhere((c) => c.dir == chDir);
      if (i < 0) return;
      if (i != _ci) {
        await _load(i);
        return;
      }
      if (_pc != null && _pc!.hasClients && page > 0) {
        _pc!.jumpToPage(page.clamp(0, _pages.length - 1));
        setState(() => _page = page);
      }
    } catch (_) {
      // 位置坏了不值得拦人，从头看。
    }
  }

  void _save(int page) {
    final ch = _chs[_ci];
    SharedPreferences.getInstance()
        .then((p) => p.setString(_posKey, '${ch.dir}|$page'))
        .catchError((_) => false);
  }

  void _onPage(int i) {
    setState(() => _page = i);
    _save(i);
    // 横向读到本话最后一页时把下一页预热上，翻过去不用等。
    if (i + 1 < _pages.length) {
      unawaited(precacheImage(
        CachedNetworkImageProvider(_pages[i + 1]),
        context,
      ).catchError((_) {}));
    }
  }

  void _gotoChapter(int d) {
    final n = _ci + d;
    if (n < 0 || n >= _chs.length) return;
    _load(n);
  }

  void _toggleZoom() {
    final next = _zoom > 1.01 ? 1.0 : 2.2;
    setState(() => _zoom = next);
    _tv.value = Matrix4.diagonal3Values(next, next, 1);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ch = _chs.isEmpty ? null : _chs[_ci];

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: _content(context)),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              ignoring: !_chrome,
              child: AnimatedOpacity(
                opacity: _chrome ? 1 : 0,
                duration: const Duration(milliseconds: 160),
                child: _topBar(cs, ch),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              ignoring: !_chrome,
              child: AnimatedOpacity(
                opacity: _chrome ? 1 : 0,
                duration: const Duration(milliseconds: 160),
                child: _bottomBar(cs),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _topBar(ColorScheme cs, MangaChapter? ch) {
    return Container(
      padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
      color: Colors.black.withValues(alpha: .62),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back, color: Colors.white),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.detail.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600),
                ),
                Text(
                  ch?.name ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => setState(() => _vertical = !_vertical),
            icon: Icon(
              _vertical ? Icons.swap_horiz : Icons.view_day_outlined,
              color: Colors.white,
            ),
            tooltip: _vertical ? '横向翻页' : '纵向连续',
          ),
        ],
      ),
    );
  }

  Widget _bottomBar(ColorScheme cs) {
    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
      color: Colors.black.withValues(alpha: .62),
      child: Row(
        children: [
          TextButton(
            onPressed: _ci > 0 ? () => _gotoChapter(-1) : null,
            child: const Text('上一话', style: TextStyle(color: Colors.white)),
          ),
          Expanded(
            child: Center(
              child: Text(
                '${_page + 1} / ${_pages.isEmpty ? 0 : _pages.length}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          ),
          TextButton(
            onPressed: _ci + 1 < _chs.length ? () => _gotoChapter(1) : null,
            child: const Text('下一话', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _content(BuildContext context) {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
        ),
      );
    }
    if (_err != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('这一话取不到', style: TextStyle(color: Colors.white)),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => _load(_ci),
              child: Text(Lc.current.retry),
            ),
          ],
        ),
      );
    }
    if (_pages.isEmpty) {
      return const Center(
        child: Text('这一话还没有图', style: TextStyle(color: Colors.white70)),
      );
    }
    return _vertical ? _scrollMode() : _pageMode();
  }

  /// 横向翻页：一屏一页，双击放大，单击切出工具栏。
  Widget _pageMode() {
    return GestureDetector(
      onTap: () => setState(() => _chrome = !_chrome),
      onDoubleTap: _toggleZoom,
      child: PageView.builder(
        controller: _pc,
        itemCount: _pages.length,
        onPageChanged: _onPage,
        itemBuilder: (_, i) {
          return InteractiveViewer(
            transformationController: i == _page ? _tv : null,
            minScale: 1,
            maxScale: 4,
            panEnabled: _zoom > 1.01,
            scaleEnabled: true,
            child: Center(
              child: CachedNetworkImage(
                imageUrl: _pages[i],
                fit: BoxFit.contain,
                fadeInDuration: const Duration(milliseconds: 80),
                placeholder: (_, _) => const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white24),
                  ),
                ),
                errorWidget: (_, _, _) => const Center(
                  child: Icon(Icons.broken_image_outlined,
                      color: Colors.white38, size: 36),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// 纵向连续：条漫那种一张接一张往下滑，不做分页。
  Widget _scrollMode() {
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n is ScrollUpdateNotification) {
          final total = n.metrics.maxScrollExtent;
          if (total > 0) {
            final p = (n.metrics.pixels / total * (_pages.length - 1))
                .round()
                .clamp(0, _pages.length - 1);
            if (p != _page) {
              setState(() => _page = p);
              _save(p);
            }
          }
        }
        return false;
      },
      child: ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: _pages.length,
        itemBuilder: (_, i) => CachedNetworkImage(
          imageUrl: _pages[i],
          fit: BoxFit.fitWidth,
          width: double.infinity,
          placeholder: (_, _) => const SizedBox(
            height: 320,
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white24),
              ),
            ),
          ),
          errorWidget: (_, _, _) => const SizedBox(
            height: 120,
            child: Center(
              child: Icon(Icons.broken_image_outlined,
                  color: Colors.white38, size: 28),
            ),
          ),
        ),
      ),
    );
  }
}
