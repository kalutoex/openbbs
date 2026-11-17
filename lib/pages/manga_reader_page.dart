import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:shared_preferences/shared_preferences.dart';

import '../img_size_store.dart';
import '../manga.dart';
import '../manga_bookmark.dart';
import '../manga_download.dart';
import '../manga_image.dart';
import '../manga_spread.dart';
import '../manga_stats.dart';
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

  /// 没有本地存档时从第几页开始（书架「继续阅读」直接续到服务端记的那一页）。
  final int initialPage;

  const MangaReaderPage({
    super.key,
    required this.detail,
    required this.index,
    this.loader,
    this.readRef,
    this.initialVertical,
    this.initialPage = 0,
  });

  @override
  State<MangaReaderPage> createState() => _MangaReaderPageState();
}

class _MangaReaderPageState extends State<MangaReaderPage> {
  List<String> _pages = const [];

  /// 这一话里已经下到手机上的页：网络地址 → 本机路径。
  /// 取图先看它，命中就直接读文件，地铁里没网也能翻。
  Map<String, String> _local = const {};
  late int _ci = widget.index;
  int _page = 0;
  bool _loading = true;
  String? _err;
  bool _chrome = true;
  ReadMode _mode = ReadMode.ltr;

  /// 从条漫切回翻页时回到哪个方向。日漫用户多半是右到左，记住上次那个。
  ReadMode _lastPaged = ReadMode.ltr;

  TapLayout _tapLayout = TapLayout.three;

  /// 点屏幕翻页（关掉就只剩「点一下出工具栏」）。
  bool _tapTurn = true;

  /// 操作反转：点左边是下一页。
  bool _tapReverse = false;

  /// 角上那点状态信息：第几页、话名、时间。
  bool _showInfo = false;

  /// 双页拆分：跨页大图拆成左右两半，各占一屏。
  bool _split = false;

  /// 双页并排：横屏时一屏摆两页。和拆页互斥（拆完再并排就是四块）。
  bool _spread = false;

  /// 现在是不是横屏。双页只在横屏生效，竖屏拿两页挤一屏，字比蚂蚁还小。
  bool _wide = false;

  /// 这本书的书签，最新的在前。
  List<MangaBookmark> _bms = const [];

  /// 这一趟读了多久。每 60 秒报一次，退出时把零头补上。
  final Stopwatch _readSw = Stopwatch();
  Timer? _statTimer;
  int _statFlushed = 0;

  /// 上一次记进统计的那一页，同一页翻来翻去只算一次。
  int _countedPage = -1;
  String _countedCh = '';

  /// 音量键翻页。
  bool _volume = true;

  /// 隐藏状态栏（沉浸式）。
  bool _hideStatus = false;

  Timer? _clock;
  final Set<String> _probing = {};

  /// 条漫那种一张接一张往下滚；其余三种都是一屏一页。
  bool get _vertical => _mode == ReadMode.scroll;

  /// 亮度只压这一页：遮一层黑，不去调系统亮度（改系统亮度会影响别的 App，
  /// 退出阅读器还得记得调回来，那是副作用不是功能）。
  double _bright = MangaPref.brightMax;

  /// 条漫两页之间留的空，0 = 接死。
  double _gap = 0;

  PageController? _pc;

  /// 纵向连续那串的滚动位置。以前没有 controller，退出再进只能从头看。
  final ScrollController _sc = ScrollController();
  final _tv = TransformationController();
  double _zoom = 1;

  /// 纵向滚到底了没。到底才浮「下一话」。
  bool _nearEnd = false;

  /// 刚点过「下一话」，两秒内别再弹，免得旧状态闪一下。
  int _endMutedUntil = 0;
  Timer? _endMute;

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
    _initKeys();
    _loadPref();
    _startStats();
    _load(_ci, resume: true);
  }

  /// 横竖屏会变（横屏才双页），每帧都问一遍 MediaQuery 不贵，但状态得落在字段上，
  /// 因为翻页、跳页这些地方不在 build 里，拿不到 context。
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final sz = MediaQuery.sizeOf(context);
    _wide = sz.width > sz.height;
  }

  /// 阅读统计只管时长：进来开始记，每 60 秒落一次盘，
  /// 这样中途被杀进程最多丢一分钟。翻页和开话各在自己的口子上记。
  void _startStats() {
    _readSw.start();
    _statTimer?.cancel();
    _statTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _flushStats(),
    );
  }

  void _flushStats() {
    final sec = _readSw.elapsed.inSeconds;
    final delta = sec - _statFlushed;
    if (delta <= 0) return;
    _statFlushed = sec;
    unawaited(MangaStats.addSeconds(delta).catchError((_) {}));
  }

  /// 一屏几页。条漫、拆页都回落到一页。
  int get _per => MangaSpread.per(
    spread: _spread && _wide,
    vertical: _vertical,
    split: _split,
  );

  /// 音量键翻页：键事件在 Activity 那层就被吃掉了，走不到 Flutter 的键盘
  /// 事件，所以只能开个通道把方向传上来。
  ///
  /// 只在阅读器活着的时候打开——否则退出去以后音量键也调不动音量。
  static const _volCh = MethodChannel('openbbs/reader');

  void _initKeys() {
    _volCh.setMethodCallHandler((call) async {
      if (call.method == 'volume') {
        var step = call.arguments == 'up' ? -1 : 1;
        if (_tapReverse) step = -step;
        _turn(step);
      }
      return null;
    });
    if (!kIsWeb) {
      unawaited(
        _volCh
            .invokeMethod<bool>('volumeKeys', {'on': _volume})
            .catchError((_) => null),
      );
    }
  }

  void _applyChrome() {
    SystemChrome.setEnabledSystemUIMode(
      _hideStatus ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }

  /// 角上那行时间三十秒走一次，别每帧都 setState。
  void _syncClock() {
    _clock?.cancel();
    _clock = null;
    if (!_showInfo) return;
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  /// 上次那套读法：方向、点屏幕、布局、拆页、状态信息、音量键、状态栏，
  /// 外加亮度和条漫页间距。一次读完，别一个开关一次 getInstance。
  Future<void> _loadPref() async {
    try {
      final m = await MangaPref.mode();
      final b = await MangaPref.brightness();
      final g = await MangaPref.gap();
      final tl = await MangaPref.tapLayout();
      final tt = await MangaPref.flag('tap_turn', true);
      final tr = await MangaPref.flag('tap_reverse', false);
      final si = await MangaPref.flag('show_info', false);
      final sp = await MangaPref.flag('split_spread', false);
      final spd = await MangaPref.flag('spread_pages', false);
      final vk = await MangaPref.flag('volume_keys', true);
      final hs = await MangaPref.flag('hide_status', false);
      if (!mounted) return;
      setState(() {
        // 显式传了 initialVertical 的页面（书源那套）以传进来的为准。
        final want = widget.initialVertical == null
            ? m
            : (widget.initialVertical! ? ReadMode.scroll : ReadMode.ltr);
        _mode = want;
        if (want != ReadMode.scroll) _lastPaged = want;
        _bright = b;
        _gap = g;
        _tapLayout = tl;
        _tapTurn = tt;
        _tapReverse = tr;
        _showInfo = si;
        _split = sp;
        _spread = spd;
        _volume = vk;
        _hideStatus = hs;
      });
      _applyChrome();
      _syncClock();
      if (!kIsWeb) {
        unawaited(
          _volCh
              .invokeMethod<bool>('volumeKeys', {'on': _volume})
              .catchError((_) => null),
        );
      }
      // 读法可能跟首次构建时不一样，页码带过去，别退回第一页。
      final keep = _page;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && keep > 0) unawaited(_jumpToPage(keep));
      });
    } catch (_) {
      // 偏好读不出来不值得拦人，用默认的看。
    }
  }

  @override
  void dispose() {
    _flushStats();
    _readSw.stop();
    _statTimer?.cancel();
    _reportTimer?.cancel();
    _endMute?.cancel();
    _clock?.cancel();
    _sendPos();
    _volCh.setMethodCallHandler(null);
    if (!kIsWeb) {
      unawaited(
        _volCh
            .invokeMethod<bool>('volumeKeys', {'on': false})
            .catchError((_) => null),
      );
    }
    if (_hideStatus) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    _pc?.dispose();
    _sc.dispose();
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
      // 这一话有离线的那几页，先记下来：取图时按地址换成本机文件。
      // 书源的书不走离线（源站地址会过期），loader 有值就不查索引。
      var local = const <String, String>{};
      if (widget.loader == null) {
        await MangaDown.i.init();
        final paths = MangaDown.i.localPages(
          widget.detail.dir,
          ch.dir,
          pages.length,
        );
        final m = <String, String>{};
        for (var i = 0; i < pages.length && i < paths.length; i++) {
          final p = paths[i];
          if (p != null) m[pages[i]] = p;
        }
        local = m;
      }
      if (!mounted) return;
      setState(() {
        _pages = pages;
        _local = local;
        _loading = false;
        _page = 0;
        _nearEnd = false;
        _countedPage = -1;
        _countedCh = '';
      });
      if (_pc != null && _pc!.hasClients) _pc!.jumpToPage(0);
      if (_sc.hasClients) _sc.jumpTo(0);
      _sendPos(force: true);
      unawaited(_reloadBms());
      unawaited(
        MangaStats.addChapter(
          widget.detail.dir,
          widget.detail.title,
        ).catchError((_) {}),
      );
      if (resume) await _restore();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _err = '$e';
      });
    }
  }

  Future<void> _reloadBms() async {
    try {
      final l = await MangaBm.list(widget.detail.dir);
      if (mounted) setState(() => _bms = l);
    } catch (_) {
      // 书签读不出来不该影响看书。
    }
  }

  /// 当前这一页有没有书签。
  bool get _hasBm {
    final ch = _ch;
    if (ch == null) return false;
    return _bms.any((b) => b.isAt(ch.dir, _page));
  }

  /// 点一下：这一页有书签就删，没有就加。
  Future<void> _toggleBm() async {
    final ch = _ch;
    if (ch == null) return;
    final page = _page;
    final had = _hasBm;
    final l = await MangaBm.toggle(
      dir: widget.detail.dir,
      chDir: ch.dir,
      chName: ch.name,
      page: page,
    );
    if (!mounted) return;
    setState(() => _bms = l);
    _toast(had ? '书签已删除' : '已加书签：第 ${page + 1} 页');
  }

  void _toast(String s) {
    final m = ScaffoldMessenger.maybeOf(context);
    m?.hideCurrentSnackBar();
    m?.showSnackBar(
      SnackBar(
        content: Text(s),
        duration: const Duration(milliseconds: 1200),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.white24,
      ),
    );
  }

  /// 上次读到第几话第几页。只有第一次进来才用得上。
  ///
  /// 本地存档优先；没有存档时用 [widget.initialPage]（书架「继续阅读」带进来的）。
  /// 横向直接 jumpToPage，纵向按图片尺寸把偏移估出来再滚过去。
  Future<void> _restore() async {
    var page = 0;
    var have = false;
    try {
      final p = await SharedPreferences.getInstance();
      // 老 key 没有账号/站点作用域，只在新 key 空着时读一次，读到就按新 key 存回去
      var raw = p.getString(_posKey);
      raw ??= p.getString(mangaLegacyPosKey(widget.detail.dir));
      if (raw != null) {
        final parts = raw.split('|');
        if (parts.length == 2) {
          final chDir = parts[0];
          final pg = int.tryParse(parts[1]) ?? 0;
          final i = _chs.indexWhere((c) => c.dir == chDir);
          if (i >= 0) {
            if (i != _ci) {
              await _load(i);
              return;
            }
            page = pg;
            have = true;
          }
        }
      }
    } catch (_) {
      // 位置坏了不值得拦人，从头看。
    }
    if (!mounted) return;
    if (!have && widget.initialPage > 0) {
      page = widget.initialPage;
      have = true;
    }
    if (!have || page <= 0) return;
    await _jumpToPage(page);
  }

  /// 翻到第几页（0 基）。横向 jumpToPage，纵向按估算偏移滚。
  Future<void> _jumpToPage(int page, {bool animate = false}) async {
    final units = _units;
    if (units.isEmpty) return;
    final target = page.clamp(0, units.length - 1);
    if (target != _page) setState(() => _page = target);
    if (!_vertical) {
      final pc = _pc;
      if (pc == null) return;
      // 页码是单页的，PageView 走的是屏号：双页时第 12 页在第 6 屏。
      final screen = MangaSpread.screenOf(target, _per);
      if (!pc.hasClients) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _pc != null && _pc!.hasClients) {
            _pc!.jumpToPage(screen);
          }
        });
        return;
      }
      if (animate) {
        await pc.animateToPage(
          screen,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      } else {
        pc.jumpToPage(screen);
      }
      return;
    }
    await _scrollToPage(target, animate: animate);
  }

  /// 纵向没有页码这个概念，只能按"前面几页一共多高"算偏移。
  ///
  /// 高度优先用 [ImgSizeStore] 里记过的真实宽高（读过的页都存过），
  /// 没见过的页按宽 1.45 倍估。跳完再对两三次——图一张张回来，总高一直在长。
  Future<void> _scrollToPage(int target, {bool animate = false}) async {
    await ImgSizeStore.ensureLoaded();
    if (!mounted) return;
    if (!_sc.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _sc.hasClients && target > 0) {
          unawaited(_scrollToPage(target));
        }
      });
      return;
    }
    final width = MediaQuery.sizeOf(context).width;
    double offsetOf() {
      var h = 0.0;
      for (var i = 0; i < target && i < _pages.length; i++) {
        final sz = ImgSizeStore.get(_pages[i]);
        final ratio = (sz != null && sz.width > 0)
            ? sz.height / sz.width
            : 1.45;
        h += width * ratio + _gap;
      }
      return h;
    }

    var t = offsetOf().clamp(0.0, _sc.position.maxScrollExtent);
    if (animate) {
      await _sc.animateTo(
        t,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      _sc.jumpTo(t);
    }
    for (var k = 0; k < 3; k++) {
      await Future<void>.delayed(const Duration(milliseconds: 260));
      if (!mounted || !_sc.hasClients) return;
      t = offsetOf().clamp(0.0, _sc.position.maxScrollExtent);
      if ((_sc.position.pixels - t).abs() < 12) return;
      _sc.jumpTo(t);
    }
  }

  /// 书签列表。点一条跳过去，右边叉掉。
  Future<void> _openBms() async {
    await _reloadBms();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF2B2B2B),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _SheetTitle('书签'),
              if (_bms.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 24),
                  child: Text(
                    '还没有书签。读到哪里想记住，点底栏那个书签图标。',
                    style: TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _bms.length,
                    itemBuilder: (_, i) {
                      final b = _bms[i];
                      final here = b.chDir == _ch?.dir && b.page == _page;
                      return ListTile(
                        dense: true,
                        title: Text(
                          b.chName.isEmpty ? '未命名话' : b.chName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: here ? Colors.amber : Colors.white,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          '第 ${b.page + 1} 页',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(
                            Icons.close,
                            size: 18,
                            color: Colors.white38,
                          ),
                          tooltip: '删除',
                          onPressed: () async {
                            final l = await MangaBm.remove(
                              dir: widget.detail.dir,
                              chDir: b.chDir,
                              page: b.page,
                            );
                            if (!mounted) return;
                            setState(() => _bms = l);
                            setSheet(() {});
                          },
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          unawaited(_goBm(b));
                        },
                      );
                    },
                  ),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// 跳到某条书签：不在这一话就先把那一话取回来。
  Future<void> _goBm(MangaBookmark b) async {
    final i = _chs.indexWhere((c) => c.dir == b.chDir);
    if (i < 0) {
      _toast('这一话已经不在目录里了');
      return;
    }
    if (i != _ci) {
      await _load(i);
      if (!mounted) return;
    }
    await _jumpToPage(b.page);
  }

  /// 点页码跳页。只收数字，越界就落在两头。
  Future<void> _askJump() async {
    final ctl = TextEditingController(text: '${_page + 1}');
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('跳到第几页'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(hintText: '1 - ${_units.length}'),
          onSubmitted: (t) => Navigator.pop(ctx, int.tryParse(t.trim())),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(ctl.text.trim())),
            child: const Text('跳转'),
          ),
        ],
      ),
    );
    ctl.dispose();
    if (v == null || !mounted) return;
    await _jumpToPage(v - 1, animate: true);
  }

  /// 这一话读到头了没。横向看最后一页、纵向滚到接近底部。
  bool get _atEnd {
    if (_loading || _err != null || _pages.isEmpty) return false;
    if (DateTime.now().millisecondsSinceEpoch < _endMutedUntil) return false;
    if (_vertical) return _nearEnd;
    final per = _per;
    final last = MangaSpread.screens(_units.length, per) - 1;
    return MangaSpread.screenOf(_page, per) >= last;
  }

  /// 读完一话点「下一话」：有下一话就翻，没有就退回详情页。
  void _onEndTap() {
    _endMutedUntil = DateTime.now().millisecondsSinceEpoch + 2000;
    _endMute?.cancel();
    _endMute = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() {});
    });
    if (_ci + 1 < _chs.length) {
      _gotoChapter(1);
      return;
    }
    Navigator.of(context).pop();
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
    unawaited(
      MangaUserApi.markRead(
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
      ),
    );
  }

  /// 翻到第几屏。[i] 是屏号，页码要换算：双页时第 6 屏是第 13 页。
  void _onPage(int i) {
    final page = MangaSpread.pageOf(i, _per).clamp(0, _units.length - 1);
    setState(() => _page = page);
    _save(page);
    _countPage(page);
    // 翻到这一屏的最后一页时把下一页预热上，翻过去不用等。
    final units = _units;
    final nextIdx = page + _per;
    if (nextIdx < units.length) {
      final next = units[nextIdx].url;
      final lp = _local[next];
      final prov = lp != null ? mangaFileProvider(lp) : null;
      if (prov != null) {
        unawaited(precacheImage(prov, context).catchError((_) {}));
      } else if (lp == null) {
        unawaited(
          precacheImage(
            CachedNetworkImageProvider(next),
            context,
          ).catchError((_) {}),
        );
      }
    }
  }

  void _countPage(int page) {
    final ch = _ch;
    if (ch == null) return;
    if (_countedCh == ch.dir && _countedPage == page) return;
    _countedCh = ch.dir;
    _countedPage = page;
    unawaited(
      MangaStats.addPage(
        widget.detail.dir,
        widget.detail.title,
      ).catchError((_) {}),
    );
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
          // 状态信息：页码、话名、时间。跟工具栏分开，工具栏缩起来也在。
          if (_showInfo) _infoBar(),
          // 读到这一话头上了才浮出来：给一个出口，别让人自己找下一话。
          if (_atEnd)
            Positioned(
              right: 16,
              bottom: MediaQuery.paddingOf(context).bottom + 84,
              child: _endTip(),
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
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
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
            onPressed: _toggleScroll,
            icon: Icon(
              _vertical ? Icons.swap_horiz : Icons.view_day_outlined,
              color: Colors.white,
            ),
            tooltip: _vertical ? '翻页' : '条漫',
          ),
          IconButton(
            onPressed: _openSettings,
            icon: const Icon(Icons.tune, color: Colors.white),
            tooltip: '阅读设置',
          ),
        ],
      ),
    );
  }

  /// 阅读设置。一个能滚的底部面板，别学以前那条塞在底栏里的窄条——
  /// 开关一多就顶到屏幕外，最后一个选项永远点不着。
  ///
  /// 改一项就存一项，不必「确定」；面板外面点一下关掉，阅读器里立刻生效。
  Future<void> _openSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF2B2B2B),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          void upd(VoidCallback fn) {
            setSheet(fn);
            if (mounted) setState(fn);
          }

          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: .82,
            minChildSize: .35,
            maxChildSize: .95,
            builder: (ctx, scroll) => ListView(
              controller: scroll,
              padding: EdgeInsets.fromLTRB(
                16,
                0,
                16,
                24 + MediaQuery.paddingOf(ctx).bottom,
              ),
              children: [
                const _SheetTitle('阅读设置'),
                const _SheetGap(),
                _sheetRow(
                  '阅读方向',
                  trailing: Wrap(
                    spacing: 8,
                    children: [
                      _dirChip('→', ReadMode.ltr, upd),
                      _dirChip('←', ReadMode.rtl, upd),
                      _dirChip('↓', ReadMode.down, upd),
                      _dirChip('↕', ReadMode.scroll, upd),
                    ],
                  ),
                ),
                _sheetRow(
                  '触屏翻页',
                  sub: _tapTurn ? '点屏幕两侧翻页，点中间出工具栏' : '点屏幕只切工具栏',
                  trailing: Switch(
                    value: _tapTurn,
                    onChanged: (v) {
                      upd(() => _tapTurn = v);
                      unawaited(MangaPref.setFlag('tap_turn', v));
                    },
                  ),
                ),
                _sheetRow(
                  '导航布局',
                  trailing: Wrap(
                    spacing: 8,
                    children: [
                      _layoutChip('三栏', TapLayout.three, upd),
                      _layoutChip('L 样式', TapLayout.lShape, upd),
                    ],
                  ),
                ),
                _sheetRow(
                  '操作反转',
                  sub: '点左侧下一页，右侧上一页',
                  trailing: Switch(
                    value: _tapReverse,
                    onChanged: (v) {
                      upd(() => _tapReverse = v);
                      unawaited(MangaPref.setFlag('tap_reverse', v));
                    },
                  ),
                ),
                _sheetRow(
                  '显示状态信息',
                  sub: '页码、话名、时间',
                  trailing: Switch(
                    value: _showInfo,
                    onChanged: (v) {
                      upd(() => _showInfo = v);
                      unawaited(MangaPref.setFlag('show_info', v));
                      _syncClock();
                    },
                  ),
                ),
                _sheetRow(
                  '双页并排',
                  sub: _wide ? '一屏两页，横屏才好读' : '横过来才生效，竖屏仍是一页',
                  trailing: Switch(
                    value: _spread,
                    onChanged: (v) {
                      final keep = _page;
                      upd(() {
                        _spread = v;
                        // 并排和拆页互斥：拆完再并排就是四块。
                        if (v) _split = false;
                      });
                      unawaited(MangaPref.setFlag('spread_pages', v));
                      if (v) {
                        unawaited(MangaPref.setFlag('split_spread', false));
                      }
                      // 屏号变了，页码带过去，别弹回第一屏。
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) unawaited(_jumpToPage(keep));
                      });
                    },
                  ),
                ),
                _sheetRow(
                  '双页拆分',
                  sub: '跨页大图拆成左右两屏',
                  trailing: Switch(
                    value: _split,
                    onChanged: (v) {
                      final keep = _page;
                      upd(() {
                        _split = v;
                        if (v) _spread = false;
                      });
                      unawaited(MangaPref.setFlag('split_spread', v));
                      if (v) {
                        unawaited(MangaPref.setFlag('spread_pages', false));
                      }
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) unawaited(_jumpToPage(keep));
                      });
                    },
                  ),
                ),
                _sheetRow(
                  '书签',
                  sub: '${_bms.length} 条',
                  trailing: TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      unawaited(_openBms());
                    },
                    child: const Text(
                      '查看',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                ),
                // 网页版和 iOS 上没有音量键这条通道，不摆这个开关。
                if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
                  _sheetRow(
                    '音量键翻页',
                    sub: '音量下翻下一页，上翻上一页',
                    trailing: Switch(
                      value: _volume,
                      onChanged: (v) {
                        upd(() => _volume = v);
                        unawaited(MangaPref.setFlag('volume_keys', v));
                        unawaited(
                          _volCh
                              .invokeMethod<bool>('volumeKeys', {'on': v})
                              .catchError((_) => null),
                        );
                      },
                    ),
                  ),
                _sheetRow(
                  '隐藏状态栏',
                  sub: '阅读时全屏，退出恢复',
                  trailing: Switch(
                    value: _hideStatus,
                    onChanged: (v) {
                      upd(() => _hideStatus = v);
                      unawaited(MangaPref.setFlag('hide_status', v));
                      _applyChrome();
                    },
                  ),
                ),
                const _SheetGap(),
                const _SheetTitle('亮度'),
                Row(
                  children: [
                    const Icon(
                      Icons.brightness_low,
                      size: 16,
                      color: Colors.white70,
                    ),
                    Expanded(
                      child: Slider(
                        value: _bright,
                        min: MangaPref.brightMin,
                        max: MangaPref.brightMax,
                        activeColor: Colors.white,
                        inactiveColor: Colors.white24,
                        onChanged: (v) => upd(() => _bright = v),
                        // 拖动时每帧都写盘没必要，松手再存。
                        onChangeEnd: (v) =>
                            unawaited(MangaPref.setBrightness(v)),
                      ),
                    ),
                    const Icon(
                      Icons.brightness_high,
                      size: 16,
                      color: Colors.white70,
                    ),
                  ],
                ),
                if (_vertical) ...[
                  const _SheetGap(),
                  const _SheetTitle('页间距'),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final g in const [0.0, 8.0, 16.0, 24.0])
                        ChoiceChip(
                          label: Text(
                            g == 0 ? '接死' : '${g.toInt()}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          selected: (_gap - g).abs() < 0.5,
                          onSelected: (_) {
                            upd(() => _gap = g);
                            unawaited(MangaPref.setGap(g));
                          },
                        ),
                    ],
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  /// 一行设置：左边标题（可带说明），右边控件。
  Widget _sheetRow(String label, {String? sub, Widget? trailing}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
                if (sub != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      sub,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }

  Widget _dirChip(String label, ReadMode m, void Function(VoidCallback) upd) {
    return _choice(
      label,
      selected: _mode == m,
      onTap: () {
        if (_mode == m) return;
        final keep = _page;
        upd(() {
          _mode = m;
          if (m != ReadMode.scroll) _lastPaged = m;
        });
        unawaited(MangaPref.setMode(m));
        if (m == ReadMode.scroll) _syncClock();
        // 两套视图各有一套滚动状态，换完把当前页带过去，别退回第一页。
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_jumpToPage(keep));
        });
      },
    );
  }

  Widget _layoutChip(
    String label,
    TapLayout v,
    void Function(VoidCallback) upd,
  ) {
    return _choice(
      label,
      selected: _tapLayout == v,
      onTap: () {
        if (_tapLayout == v) return;
        upd(() => _tapLayout = v);
        unawaited(MangaPref.setTapLayout(v));
      },
    );
  }

  Widget _choice(
    String label, {
    required bool selected,
    required VoidCallback onTap,
  }) {
    return choiceChipBox(label, selected: selected, onTap: onTap);
  }

  /// 条漫 ↔ 翻页的快切。翻页方向用上次那个，临时看一眼条漫再切回来不会丢。
  void _toggleScroll() {
    final keep = _page;
    final next = _vertical ? _lastPaged : ReadMode.scroll;
    setState(() {
      _mode = next;
      if (next != ReadMode.scroll) _lastPaged = next;
    });
    unawaited(MangaPref.setMode(next));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_jumpToPage(keep));
    });
  }

  /// 角上那块状态信息。压在图上，手指点得穿过去。
  Widget _infoBar() {
    final ch = _ch;
    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    return Positioned(
      left: 12,
      top: MediaQuery.paddingOf(context).top + 8,
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: _chrome ? .35 : 1, // 工具栏露出来的时候这块就该让位
          duration: const Duration(milliseconds: 160),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: .45),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${_page + 1} / ${_units.length}',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
                if (ch != null)
                  Text(
                    ch.name,
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                Text(
                  '$hh:$mm',
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
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
          Row(
            children: [
              TextButton(
                onPressed: _ci > 0 ? () => _gotoChapter(-1) : null,
                child: const Text('上一话', style: TextStyle(color: Colors.white)),
              ),
              IconButton(
                onPressed: _pages.isEmpty ? null : _toggleBm,
                onLongPress: _openBms,
                visualDensity: VisualDensity.compact,
                iconSize: 20,
                icon: Icon(
                  _hasBm ? Icons.bookmark : Icons.bookmark_border,
                  color: _hasBm ? Colors.amber : Colors.white70,
                ),
                tooltip: '本页书签（长按看全部）',
              ),
              Expanded(
                child: Center(
                  child: TextButton(
                    onPressed: _pages.isEmpty ? null : _askJump,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 34),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    child: Text(
                      MangaSpread.label(_page, _units.length, _per),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
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

  /// 读完一话浮出来的那颗按钮。有下一话就翻，没有就说明到头了。
  Widget _endTip() {
    final hasNext = _ci + 1 < _chs.length;
    return Material(
      color: Colors.white.withValues(alpha: .92),
      borderRadius: BorderRadius.circular(22),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: _onEndTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                hasNext ? '下一话' : '已是最后一话',
                style: const TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (hasNext) ...[
                const SizedBox(width: 2),
                const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: Colors.black87,
                ),
              ],
            ],
          ),
        ),
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
    return _vertical ? _scrollMode() : _pagedMode();
  }

  /// 翻页：一屏一页，双击放大，点两侧翻页。
  ///
  /// 方向、拆页都落在这里：`reverse` 把 PageView 反过来就是右到左，
  /// `Axis.vertical` 就是一屏一页的上下翻。
  Widget _pagedMode() {
    final units = _units;
    final per = _per;
    final screens = MangaSpread.screens(units.length, per);
    final swipeAxis = _mode == ReadMode.down ? Axis.vertical : Axis.horizontal;
    return GestureDetector(
      onTapUp: _onTap,
      onDoubleTap: per > 1 ? null : _toggleZoom,
      child: PageView.builder(
        controller: _pc,
        scrollDirection: swipeAxis,
        reverse: _mode == ReadMode.rtl,
        itemCount: screens,
        onPageChanged: _onPage,
        itemBuilder: (_, i) {
          if (per == 1) {
            final u = units[i];
            return InteractiveViewer(
              transformationController: i == _page ? _tv : null,
              minScale: 1,
              maxScale: 4,
              panEnabled: _zoom > 1.01,
              scaleEnabled: true,
              child: Center(
                child: u.half == null
                    ? _img(
                        u.url,
                        fit: BoxFit.contain,
                        bustCache: true,
                        probeSize: true,
                      )
                    : _halfImage(u.url, u.ratio ?? 1.4, u.half!),
              ),
            );
          }
          // 双页并排：一屏两页，各自 contain 在自己那一半里。
          final a = i * per;
          final b = a + 1;
          final left = b < units.length ? units[b] : null;
          final right = units[a];
          // 右到左的书，先看右边那页：左位放第 b 页。
          final pair = _mode == ReadMode.rtl ? [left, right] : [right, left];
          return Row(
            children: [
              for (final u in pair)
                Expanded(
                  child: u == null
                      ? const SizedBox.shrink()
                      : Center(
                          child: u.half == null
                              ? _img(
                                  u.url,
                                  fit: BoxFit.contain,
                                  bustCache: true,
                                  probeSize: true,
                                )
                              : _halfImage(u.url, u.ratio ?? 1.4, u.half!),
                        ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// 一页图。本机下过就直接读文件（没网也能看），没下过就走原来那套网络取图。
  ///
  /// 文件坏了（下了一半断了、被清理掉）回落到网络，不让读者对着一块空白。
  Widget _img(
    String url, {
    required BoxFit fit,
    Alignment alignment = Alignment.center,
    bool bustCache = false,
    bool probeSize = true,
    double? placeholderHeight,
  }) {
    Widget net() => RetryImage(
      url: url,
      fit: fit,
      alignment: alignment,
      bustCache: bustCache,
      probeSize: probeSize,
      placeholderHeight: placeholderHeight,
    );
    final lp = _local[url];
    if (lp != null) {
      final w = mangaFileImage(
        lp,
        fit: fit,
        alignment: alignment,
        fallback: net,
      );
      if (w != null) return w;
    }
    return net();
  }

  /// 跨页大图的一半：整幅按屏高铺满，再按左/右贴边裁一半。
  ///
  /// 用 OverflowBox 让整幅图超出屏幕，ClipRect 只留半边——比先裁图再缩放
  /// 省一次解码，也不会因为两半各自缩放导致接缝对不上。
  Widget _halfImage(String url, double ratio, Alignment align) {
    return ClipRect(
      child: LayoutBuilder(
        builder: (context, c) {
          final h = c.maxHeight.isFinite
              ? c.maxHeight
              : MediaQuery.sizeOf(context).height;
          final w = h * ratio;
          return OverflowBox(
            alignment: align,
            maxWidth: w,
            maxHeight: h,
            child: SizedBox(
              width: w,
              height: h,
              child: _img(
                url,
                fit: BoxFit.fill,
                bustCache: true,
                probeSize: true,
              ),
            ),
          );
        },
      ),
    );
  }

  /// 纵向连续：条漫那种一张接一张往下滑，不做分页。
  Widget _scrollMode() {
    // 一话短到撑不满一屏时滚不动，也就没有「滚到底」这个事件——布局稳定后补判一次。
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (n) {
        final near =
            n.metrics.maxScrollExtent <= 0 || n.metrics.extentAfter < 160;
        if (near != _nearEnd && mounted) setState(() => _nearEnd = near);
        return false;
      },
      child: NotificationListener<ScrollNotification>(
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
                _countPage(p);
              }
              final near = n.metrics.extentAfter < 160;
              if (near != _nearEnd) setState(() => _nearEnd = near);
            }
          }
          return false;
        },
        child: GestureDetector(
          onTapUp: _onTap,
          child: ListView.builder(
            controller: _sc,
            padding: EdgeInsets.zero,
            itemCount: _pages.length,
            // 一屏放几张就建几张，长话滚下去也不会一次解码五十多张图。
            scrollCacheExtent: const ScrollCacheExtent.pixels(1200),
            itemBuilder: (_, i) => Padding(
              padding: EdgeInsets.only(
                bottom: (i + 1 == _pages.length) ? 0 : _gap,
              ),
              child: SizedBox(
                width: double.infinity,
                child: _img(
                  _pages[i],
                  fit: BoxFit.fitWidth,
                  bustCache: true,
                  probeSize: false,
                  placeholderHeight: 320,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------ 显示单元

  /// 一屏要显示的东西。普通情况就是一张图；开了双页拆分，跨页大图拆成两屏。
  ///
  /// 页码、跳页、翻页都按这个列表走，不然拆了页以后页码对不上真实页数。
  List<_Unit> get _units {
    // 条漫是连着滚的，拆页没有意义，只在翻页时拆。
    if (!_split || _vertical) return [for (final u in _pages) _Unit(u)];
    final out = <_Unit>[];
    for (final u in _pages) {
      final sz = ImgSizeStore.get(u);
      if (sz == null || sz.height <= 0) {
        // 尺寸还不知道，先按整页摆；量到了会 setState 重新拆。
        _probeSize(u);
        out.add(_Unit(u));
        continue;
      }
      final ratio = sz.width / sz.height;
      if (ratio < 1.15) {
        out.add(_Unit(u));
        continue;
      }
      // 右到左的书，一页跨页图先看右半边。
      final rightFirst = _mode == ReadMode.rtl;
      out.add(_Unit(u, Alignment.centerRight, ratio));
      out.add(_Unit(u, Alignment.centerLeft, ratio));
      if (!rightFirst) {
        final a = out[out.length - 2];
        final b = out[out.length - 1];
        out[out.length - 2] = b;
        out[out.length - 1] = a;
      }
    }
    return out;
  }

  /// 量一张图的真实宽高，量到就重画一次。失败就算了，按整页读。
  void _probeSize(String url) {
    if (!_probing.add(url)) return;
    final lp = _local[url];
    final fileProv = lp == null ? null : mangaFileProvider(lp);
    final ImageProvider prov = fileProv ?? CachedNetworkImageProvider(url);
    final stream = prov.resolve(ImageConfiguration.empty);
    late final ImageStreamListener l;
    l = ImageStreamListener(
      (info, _) {
        stream.removeListener(l);
        _probing.remove(url);
        unawaited(
          ImgSizeStore.put(
            url,
            Size(info.image.width.toDouble(), info.image.height.toDouble()),
          ),
        );
        if (mounted) setState(() {});
      },
      onError: (_, _) {
        stream.removeListener(l);
        _probing.remove(url);
      },
    );
    stream.addListener(l);
  }

  // ------------------------------------------------------------ 点屏幕

  /// 点屏幕：两侧翻页，中间切工具栏；关了触屏翻页就只剩切工具栏。
  ///
  /// 「哪边是下一页」取决于阅读方向——右到左的书，左边才是下一页。
  /// 操作反转再把两边对调一次。
  void _onTap(TapUpDetails d) {
    if (!_tapTurn) {
      setState(() => _chrome = !_chrome);
      return;
    }
    final size = MediaQuery.sizeOf(context);
    final x = d.localPosition.dx;
    final y = d.localPosition.dy;
    int side;
    if (_tapLayout == TapLayout.lShape) {
      // L 样式：右边一条 + 底下一条都是「下一页」，左边一条是「上一页」。
      if (x > size.width * .62 ||
          (y > size.height * .8 && x > size.width * .18)) {
        side = 1;
      } else if (x < size.width * .32) {
        side = -1;
      } else {
        side = 0;
      }
    } else {
      side = x < size.width * .34 ? -1 : (x > size.width * .66 ? 1 : 0);
    }
    if (side == 0) {
      setState(() => _chrome = !_chrome);
      return;
    }
    var next = (side > 0) == (_mode != ReadMode.rtl);
    if (_tapReverse) next = !next;
    _turn(next ? 1 : -1);
  }

  /// 翻一屏。step = 1 下一页，-1 上一页。翻到头就停，不跨话——
  /// 跨话是那颗「下一话」的事，误触一下跑到下一话很烦。
  void _turn(int step) {
    if (_pages.isEmpty) return;
    _endMutedUntil = 0;
    if (_vertical) {
      if (!_sc.hasClients) return;
      final pos = _sc.position;
      final target = (pos.pixels + step * pos.viewportDimension * .92).clamp(
        0.0,
        pos.maxScrollExtent,
      );
      if ((target - pos.pixels).abs() < 1) return;
      unawaited(
        _sc.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        ),
      );
      return;
    }
    // 双页时一屏两页，翻一次要跨两页，不然会停在半屏上。
    final per = _per;
    final cur = MangaSpread.screenOf(_page, per);
    final last = MangaSpread.screens(_units.length, per) - 1;
    final target = cur + step;
    if (target < 0 || target > last) return;
    unawaited(_jumpToPage(MangaSpread.pageOf(target, per), animate: true));
  }
}

/// 一屏要显示的内容。
class _Unit {
  final String url;

  /// 双页拆开的那一半；null = 整张图。
  final Alignment? half;

  /// 图的宽高比（拆页时要按它算整幅宽）。
  final double? ratio;

  const _Unit(this.url, [this.half, this.ratio]);
}

/// 设置面板上那种可选的方块。
Widget choiceChipBox(
  String label, {
  required bool selected,
  required VoidCallback onTap,
}) {
  return Material(
    color: selected ? const Color(0xFF2D7FF9) : Colors.white10,
    borderRadius: BorderRadius.circular(10),
    child: InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white70,
            fontSize: 13,
          ),
        ),
      ),
    ),
  );
}

class _SheetTitle extends StatelessWidget {
  final String text;
  const _SheetTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SheetGap extends StatelessWidget {
  const _SheetGap();

  @override
  Widget build(BuildContext context) => const SizedBox(height: 10);
}
