import 'package:flutter/material.dart';

import '../site_config.dart';
import '../api.dart';
import '../store.dart';
import '../widgets/skeleton.dart';
import '../widgets/thread_tile.dart';
import 'search_page.dart';
import 'thread_page.dart';

/// 时间线：全站最新的帖子。
class FeedTab extends StatefulWidget {
  final VoidCallback onMenu;

  const FeedTab({super.key, required this.onMenu});

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
  int _seen = 0;
  /// 请求代号：刷新会换号，旧请求回来自动作废。
  int _seq = 0;

  /// 这次显示的是本地缓存（连不上服务器）
  bool _offline = false;

  /// 滑过一屏就把「回到顶部」露出来。
  bool _showTop = false;

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
      });
    } on ApiException catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _first = false;
        _err = e.message;
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
        _err = e.message;
      });
    } finally {
      if (seq == _seq) _busy = false;
    }
  }

  void _open(Map<String, dynamic> it) {
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

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: widget.onMenu,
          icon: const Icon(Icons.menu),
          tooltip: '菜单',
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
            tooltip: '搜索',
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (v) {
              if (v == 'refresh') _reload();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'refresh', child: Text('刷新')),
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
              tooltip: '回到顶部',
              child: const Icon(Icons.arrow_upward, size: 20),
            )
          : null,
      body: Column(
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
                          '连不上服务器，这是上次的缓存',
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onTertiaryContainer,
                          ),
                        ),
                      ),
                      Text(
                        '重试',
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
                separatorBuilder: (_, _) =>
                    Divider(height: 1, color: cs.outlineVariant),
                itemBuilder: (context, i) {
                  if (i == _items.length) {
                    if (_err != null) {
                      return Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(
                          child: Text(_err!, style: TextStyle(color: cs.error)),
                        ),
                      );
                    }
                    if (_items.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.only(top: 120),
                        child: Center(child: Text('还没有人发帖')),
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: _hasMore
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text('到底了', style: TextStyle(color: cs.outline)),
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
  }
}
