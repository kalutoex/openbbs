import 'package:flutter/material.dart';

import '../site_config.dart';
import '../api.dart';
import '../store.dart';
import '../widgets/page_width.dart';
import '../widgets/empty_view.dart';
import '../widgets/skeleton.dart';
import '../widgets/thread_tile.dart';
import 'search_page.dart';
import 'thread_page.dart';

import '../l10n/error_text.dart';
import '../l10n/l10n.dart';

/// 时间线：全站最新的帖子。
class FeedTab extends StatefulWidget {
  final VoidCallback onMenu;
  final VoidCallback? onCompose;

  const FeedTab({super.key, required this.onMenu, this.onCompose});

  @override
  State<FeedTab> createState() => _FeedTabState();
}

class _FeedTabState extends State<FeedTab> {
  final List<Map<String, dynamic>> _items = [];
  final ScrollController _scroll = ScrollController();
  int _page = 1;
  bool _busy = false;
  bool _hasMore = true;
  bool _first = true;
  String? _err;

  /// 冷启动静默重试的次数。第一次进软件时网络栈往往还没就绪，
  /// 这时候把「连不上服务器」甩给用户没意义——先自己再试两回。
  int _coldRetry = 0;
  int _seen = 0;

  /// 请求代号：刷新会换号，旧请求回来自动作废。
  int _seq = 0;

  /// 这次显示的是本地缓存（连不上服务器）
  bool _offline = false;

  /// 滑过一屏就把「回到顶部」露出来。
  bool _showTop = false;

  /// 宽屏右栏正在看的帖子；空着就是单栏。
  int? _selId;
  String _selTitle = '';

  /// MD3 的 expanded 档：右栏放得下详情。
  bool get _wide => MediaQuery.sizeOf(context).width >= 840;

  void _onScroll() {
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - _ahead) {
      _load();
    }
    final show = _scroll.hasClients && _scroll.position.pixels > 700;
    if (show != _showTop && mounted) setState(() => _showTop = show);
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _seen = AppState.instance.feedVersion;
    AppState.instance.addListener(_onState);
    AppState.instance.feedSort.addListener(_onSort);
    _reload();
  }

  void _onState() {
    final v = AppState.instance.feedVersion;
    if (v != _seen) {
      _seen = v;
      _reload();
    }
  }

  void _onSort() {
    if (!mounted) return;
    setState(() {
      _items.clear();
      _page = 1;
      _hasMore = true;
      _first = true;
    });
    _reload();
  }

  /// 离底还有一屏就开始拉下一页，滑到底时内容已经在手上了。
  double get _ahead {
    final vp = _scroll.hasClients ? _scroll.position.viewportDimension : 0.0;
    return vp > 0 ? vp : 400;
  }

  @override
  void dispose() {
    AppState.instance.feedSort.removeListener(_onSort);
    AppState.instance.removeListener(_onState);
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    // 领个新号。正在飞的旧请求回来就直接作废，否则会把旧页拼到刷新后的列表上。
    final seq = ++_seq;
    _busy = true;
    // 列表里已经有内容时静默刷新：以前这里会先清空 + 置回骨架屏，
    // 下拉刷新和发完帖回来都会整页闪一下。现在只有第一次才挂骨架。
    if (_items.isEmpty) {
      setState(() {
        _first = true;
        _err = null;
      });
    }
    try {
      final d = await Api.get(
        '/feed',
        query: {'page': '1', 'sort': AppState.instance.feedSort.value},
        cache: true,
      );
      final cached = Api.lastFromCache;
      final items = (d['items'] as List).cast<Map<String, dynamic>>();
      if (!mounted || seq != _seq) return;
      setState(() {
        _items
          ..clear()
          ..addAll(items);
        _hasMore = items.length >= 20 && !cached;
        _page = 2;
        _first = false;
        _err = null;
        _offline = cached;
        _coldRetry = 0;
      });
    } on ApiException catch (e) {
      if (!mounted || seq != _seq) return;
      // 首屏还没出过内容、又是连不上：不报错，自己再来一次。
      // 清后台后第一次打开就撞这个，用户看到的应该是首页，不是错误提示。
      if (_items.isEmpty && e.code == 'connectFailed' && _coldRetry < 2) {
        _coldRetry++;
        _busy = false;
        Future<void>.delayed(Duration(milliseconds: 1200 * _coldRetry), () {
          if (mounted && seq == _seq) _reload();
        });
        return;
      }
      setState(() {
        _first = false;
        _err = errorText(context, e);
        _offline = false;
      });
    } finally {
      if (seq == _seq) _busy = false;
    }
  }

  Future<void> _load() async {
    if (_busy || !_hasMore || _offline) return;
    final seq = _seq;
    _busy = true;
    try {
      final d = await Api.get(
        '/feed',
        query: {'page': '$_page', 'sort': AppState.instance.feedSort.value},
      );
      final items = (d['items'] as List).cast<Map<String, dynamic>>();
      if (!mounted || seq != _seq) return;
      setState(() {
        _items.addAll(items);
        _hasMore = items.length >= 20;
        _page++;
        _first = false;
        _err = null;
      });
    } on ApiException catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _first = false;
        _err = errorText(context, e);
      });
    } finally {
      if (seq == _seq) _busy = false;
    }
  }

  void _open(Map<String, dynamic> it) {
    // 宽屏右栏放得下详情，就不跳页了。
    if (_wide) {
      setState(() {
        _selId = it['id'] as int;
        _selTitle = (it['title'] ?? '') as String;
      });
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ThreadPage(
          threadId: it['id'] as int,
          title: (it['title'] ?? '') as String,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return PopScope(
      // 右栏开着时，返回键先关右栏，不退出页面。
      canPop: !(_wide && _selId != null),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _selId = null);
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            onPressed: widget.onMenu,
            icon: const Icon(Icons.menu),
            tooltip: Lc.current.menu,
          ),
          titleSpacing: 0,
          title: Text(
            SiteConfig.brand,
            style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          actions: [
            IconButton(
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const SearchPage())),
              icon: const Icon(Icons.search),
              tooltip: Lc.current.search,
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (v) {
                if (v == 'refresh') _reload();
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'refresh',
                  child: Text(Lc.current.refresh),
                ),
              ],
            ),
          ],
        ),
        floatingActionButton: _showTop
            ? FloatingActionButton.small(
                onPressed: () => _scroll.animateTo(
                  0,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                ),
                tooltip: Lc.current.backToTop,
                child: const Icon(Icons.arrow_upward, size: 20),
              )
            : null,
        body: Builder(
          builder: (context) {
            // 宽屏且有选中帖子时左右分栏，列表不动，右边看详情。
            final list = PageWidth(
              child: Column(
                children: [
                  if (_offline)
                    Material(
                      color: cs.tertiaryContainer,
                      child: InkWell(
                        onTap: _reload,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.cloud_off,
                                size: 15,
                                color: cs.onTertiaryContainer,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  Lc.current.offlineCacheFeed,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: cs.onTertiaryContainer,
                                  ),
                                ),
                              ),
                              Text(
                                Lc.current.retry,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: cs.onTertiaryContainer,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _reload,
                      child: _first
                          ? const SkeletonList()
                          : ListView.separated(
                              controller: _scroll,
                              physics: const AlwaysScrollableScrollPhysics(),
                              itemCount: _items.length + 1,
                              // 卡片自带描边和间距，不再要分割线。
                              separatorBuilder: (_, _) =>
                                  const SizedBox.shrink(),
                              itemBuilder: (context, i) {
                                if (i == _items.length) {
                                  if (_err != null) {
                                    return EmptyView(
                                      icon: Icons.cloud_off_rounded,
                                      title: Lc.current.loadFailed,
                                      hint: _err,
                                      error: true,
                                      action: FilledButton.tonal(
                                        onPressed: _reload,
                                        child: Text(Lc.current.retry),
                                      ),
                                    );
                                  }
                                  if (_items.isEmpty) {
                                    return EmptyView(
                                      icon: Icons.forum_outlined,
                                      title: Lc.current.noPostsYet,
                                      hint: Lc.current.noPostsHint,
                                      action: widget.onCompose == null
                                          ? null
                                          : FilledButton.tonalIcon(
                                              onPressed: widget.onCompose,
                                              icon: const Icon(
                                                Icons.edit_outlined,
                                                size: 18,
                                              ),
                                              label: Text(Lc.current.newThread),
                                            ),
                                    );
                                  }
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 20,
                                    ),
                                    child: Center(
                                      child: _hasMore
                                          ? const SizedBox(
                                              height: 20,
                                              width: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : Text(
                                              Lc.current.endOfList,
                                              style: TextStyle(
                                                color: cs.outline,
                                              ),
                                            ),
                                    ),
                                  );
                                }
                                final it = _items[i];
                                return ThreadTile(
                                  item: it,
                                  onTap: () => _open(it),
                                  onDeleted: _reload,
                                );
                              },
                            ),
                    ),
                  ),
                ],
              ),
            );
            if (!_wide || _selId == null) return list;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 5, child: list),
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: cs.outlineVariant.withValues(alpha: .35),
                ),
                Expanded(
                  flex: 7,
                  child: ThreadPage(
                    key: ValueKey(_selId),
                    embedded: true,
                    threadId: _selId!,
                    title: _selTitle,
                    onClose: () => setState(() => _selId = null),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
