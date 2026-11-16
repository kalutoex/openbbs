import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:shared_preferences/shared_preferences.dart';

import '../manga.dart';
import '../manga_user.dart';
import '../read_pos.dart';
import '../store.dart';
import '../widgets/retry_image.dart';

import '../l10n/l10n.dart';
/// 看漫画。
///
/// 两种读法：横向翻页（单页，双击放大）和纵向连续（条漫、长页）。
/// 位置按书存，退出再进来接着上次那一话那一页。
///
/// 图片走 [RetryImage]：网页版上裸 CachedNetworkImage 会走 <img> 那条路，
/// 滑几屏之后纹理被回收、缓存里又记着「已解码」，结果一整片黑。
/// 书源的图还得带「重试时让后端也重新取」——后端存了一张坏的，
/// 只清本地缓存是清不掉的。
class MangaReaderPage extends StatefulWidget {
  final MangaDetail detail;
  final int index;

  /// 图片从哪来。本地书架走 [MangaApi.pages]（磁盘目录），
  /// 书源那套走 SourceApi，两边共用这一个阅读器。
  final Future<List<String>> Function(MangaChapter ch)? loader;

  /// 这本书的身份，用来往「浏览历史」里记一条。空着就不记。
  final ReadRef? readRef;

  /// 书源的图经过后端转一道，一话又长，默认顺着往下滑更像看条漫。
  ///
  /// 显式传了就听传的；不传就按上次在这台机器上的选择（[MangaPref]）走，
  /// 第一回没选过才落到 false。以前三处页面各写死一个值，用户切了也白切。
  final bool? initialVertical;

  const MangaReaderPage({
    super.key,
    required this.detail,
    required this.index,
    this.loader,
    this.readRef,
    this.initialVertical,
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
  late bool _vertical = widget.initialVertical ?? false;

  /// 亮度只压这一页：遮一层黑，不去调系统亮度（改系统亮度会影响别的 App，
  /// 退出阅读器还得记得调回来，那是副作用不是功能）。
  double _bright = MangaPref.brightMax;
  /// 条漫两页之间留的空，0 = 接死。
  double _gap = 0;
  /// 底下那条设置栏开着没。
  bool _panel = false;

  PageController? _pc;
  final _tv = TransformationController();
  double _zoom = 1;

  /// 上报节流：翻页一次一次发会把接口打爆，1.2 秒内只记最后一次。
  int _lastReportAt = 0;
  Timer? _reportTimer;

  /// 字号级别的细节不重要，这里只关心「读到哪」。
  String get _posKey => mangaPosKey(widget.detail.dir);

  List<MangaChapter> get _chs => widget.detail.chapters;

  MangaChapter? get _ch => _chs.isEmpty ? null : _chs[_ci];

  @override
  void initState() {
    super.initState();
    _pc = PageController();
    _loadPref();
    _load(_ci, resume: true);
  }

  /// 上次的读法/亮度/页间距。显式传了 initialVertical 的话，那个优先。
  Future<void> _loadPref() async {
    try {
      final v = await MangaPref.vertical();
      final b = await MangaPref.brightness();
      final g = await MangaPref.gap();
      if (!mounted) return;
      setState(() {
        if (widget.initialVertical == null && v != null) _vertical = v;
        _bright = b;
        _gap = g;
      });
    } catch (_) {
      // 偏好读不出来不值得拦人，用默认的看。
    }
  }

  @override
  void dispose() {
    _reportTimer?.cancel();
    _sendPos();
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
      final pages = widget.loader != null
          ? await widget.loader!(ch)
          : await MangaApi.pages(widget.detail.dir, ch.dir);
      if (!mounted) return;
      setState(() {
        _pages = pages;
        _loading = false;
        _page = 0;
      });
      if (_pc != null && _pc!.hasClients) _pc!.jumpToPage(0);
      _sendPos(force: true);
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
      // 老 key 没有账号/站点作用域，只在新 key 空着时读一次，读到就按新 key 存回去
      var raw = p.getString(_posKey);
      raw ??= p.getString(mangaLegacyPosKey(widget.detail.dir));
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
    final ch = _ch;
    if (ch == null) return;
    SharedPreferences.getInstance()
        .then((p) => p.setString(_posKey, '${ch.dir}|$page'))
        .catchError((_) => false);
    _sendPos();
  }

  /// 记到服务端，给「我的-浏览历史」看。本地那份还是 SharedPreferences，
  /// 那是「这本续到哪」；服务端这份是「看过什么」，两码事。
  void _sendPos({bool force = false}) {
    final r = widget.readRef;
    final ch = _ch;
    if (r == null || ch == null || _pages.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force && now - _lastReportAt < 1200) {
      _reportTimer?.cancel();
      _reportTimer = Timer(
        Duration(milliseconds: 1200 - (now - _lastReportAt)),
        _sendPos,
      );
      return;
    }
    _lastReportAt = now;
    unawaited(MangaUserApi.markRead(
      kind: r.kind,
      ref: r.ref,
      sourceId: r.sourceId,
      title: r.title,
      author: r.author,
      cover: r.cover,
      chapter: ch.name,
      chapterRef: ch.dir,
      page: _page,
      total: _pages.length,
    ));
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
    final ch = _ch;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: _content(context)),
          // 压暗：只盖图，不盖上下两条工具条，不然调到暗处连按钮都找不着。
          if (_bright < MangaPref.brightMax - .001)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: Colors.black.withValues(alpha: 1 - _bright),
                ),
              ),
            ),
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
            onPressed: () {
              final next = !_vertical;
              setState(() => _vertical = next);
              unawaited(MangaPref.setVertical(next));
            },
            icon: Icon(
              _vertical ? Icons.swap_horiz : Icons.view_day_outlined,
              color: Colors.white,
            ),
            tooltip: _vertical ? '横向翻页' : '纵向连续',
          ),
          IconButton(
            onPressed: () => setState(() => _panel = !_panel),
            icon: Icon(_panel ? Icons.tune : Icons.brightness_6_outlined,
                color: Colors.white),
            tooltip: '亮度与页间距',
          ),
        ],
      ),
    );
  }

  /// 亮度滑条 + 条漫页间距。压暗是盖一层黑，退出阅读器就没了。
  Widget _settings(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.brightness_low, size: 16, color: Colors.white70),
              Expanded(
                child: Slider(
                  value: _bright,
                  min: MangaPref.brightMin,
                  max: MangaPref.brightMax,
                  activeColor: Colors.white,
                  inactiveColor: Colors.white24,
                  onChanged: (v) {
                    // 拖动时每帧都写盘没必要，松手再存。
                    setState(() => _bright = v);
                  },
                  onChangeEnd: (v) => unawaited(MangaPref.setBrightness(v)),
                ),
              ),
              const Icon(Icons.brightness_high, size: 16, color: Colors.white70),
            ],
          ),
          if (_vertical)
            Row(
              children: [
                const SizedBox(width: 4),
                const Text('页间距',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(width: 8),
                for (final g in const [0.0, 8.0, 16.0, 24.0])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(g == 0 ? '接死' : '${g.toInt()}',
                          style: const TextStyle(fontSize: 11)),
                      selected: (_gap - g).abs() < 0.5,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onSelected: (_) {
                        setState(() => _gap = g);
                        unawaited(MangaPref.setGap(g));
                      },
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _bottomBar(ColorScheme cs) {
    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
      color: Colors.black.withValues(alpha: .62),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_panel) _settings(cs),
          Row(
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
              child: RetryImage(
                url: _pages[i],
                fit: BoxFit.contain,
                bustCache: true,
                probeSize: false,
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
      child: GestureDetector(
        onTap: () => setState(() => _chrome = !_chrome),
        child: ListView.builder(
          padding: EdgeInsets.zero,
          itemCount: _pages.length,
          // 一屏放几张就建几张，长话滚下去也不会一次解码五十多张图。
          scrollCacheExtent: const ScrollCacheExtent.pixels(1200),
          itemBuilder: (_, i) => Padding(
            padding: EdgeInsets.only(
                bottom: (i + 1 == _pages.length) ? 0 : _gap),
            child: SizedBox(
              width: double.infinity,
              child: RetryImage(
                url: _pages[i],
                fit: BoxFit.fitWidth,
                bustCache: true,
                probeSize: false,
                placeholderHeight: 320,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
