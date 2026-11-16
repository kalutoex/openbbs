import 'dart:async';

import 'package:flutter/material.dart';

import '../widgets/manga_card.dart';
import '../widgets/page_width.dart';
import '../zmh.dart';
import 'zmh_book_page.dart';

/// 再漫画排行榜：人气 / 最新 / 好评三个榜。
///
/// 书架顶上那一排只有十几本，看着不过瘾；这个页是「整页往下翻」的入口，
/// 每滑到底自动接下一页，翻到第 50 页就不给了（再往后源站也没多少新书，
/// 只是同一批反复出现，白费流量）。
///
/// 书还是点开就看，不下载、不进书架——跟推荐位同一套路。
class MangaRankPage extends StatefulWidget {
  final String initialType;

  const MangaRankPage({super.key, this.initialType = '0'});

  @override
  State<MangaRankPage> createState() => _MangaRankPageState();
}

class _MangaRankPageState extends State<MangaRankPage>
    with SingleTickerProviderStateMixin {
  static const _maxPage = 50;

  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    final i = ZmhApi.rankTabs.indexWhere((t) => t.$1 == widget.initialType);
    _tab = TabController(
        length: ZmhApi.rankTabs.length, vsync: this, initialIndex: i < 0 ? 0 : i);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('排行榜', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        bottom: TabBar(
          controller: _tab,
          tabs: [for (final t in ZmhApi.rankTabs) Tab(text: t.$2)],
        ),
      ),
      body: PageWidth(
        max: 1100,
        child: TabBarView(
          controller: _tab,
          children: [
            for (final t in ZmhApi.rankTabs)
              _RankList(key: ValueKey(t.$1), type: t.$1, maxPage: _maxPage),
          ],
        ),
      ),
    );
  }
}

class _RankList extends StatefulWidget {
  final String type;
  final int maxPage;

  const _RankList({super.key, required this.type, required this.maxPage});

  @override
  State<_RankList> createState() => _RankListState();
}

class _RankListState extends State<_RankList>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _sc = ScrollController();
  final List<ZmhBook> _books = [];
  int _page = 0;
  bool _loading = false;
  bool _done = false;
  bool _first = true;
  String? _err;

  /// 从详情页回来时 +1，让封面重新解码（CanvasKit 的老毛病）。
  int _epoch = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _sc.addListener(_onScroll);
    unawaited(_loadMore());
  }

  @override
  void dispose() {
    _sc.removeListener(_onScroll);
    _sc.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_sc.hasClients || _loading || _done || _err != null) return;
    if (_sc.position.extentAfter < 600) unawaited(_loadMore());
  }

  Future<void> _loadMore() async {
    if (_loading || _done) return;
    if (_page >= widget.maxPage) {
      setState(() => _done = true);
      return;
    }
    setState(() => _loading = true);
    final next = _page + 1;
    final r = await ZmhApi.rank(widget.type, page: next);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _first = false;
      if (r.error) {
        _err = '榜单取不到';
        // 一页都没拿到就是真失败；中途失败只提示一下，不把已翻出来的清掉
        if (_books.isEmpty) _done = true;
        return;
      }
      _err = null;
      // 源站页与页之间会重排，同一本可能重复出现，按 id 剔掉
      final have = {for (final b in _books) b.id};
      final fresh = r.list.where((b) => !have.contains(b.id)).toList();
      _books.addAll(fresh);
      _page = next;
      if (r.list.isEmpty || fresh.isEmpty) _done = true;
    });
  }

  Future<void> _reload() async {
    setState(() {
      _books.clear();
      _page = 0;
      _done = false;
      _first = true;
      _err = null;
    });
    await _loadMore();
  }

  Future<void> _open(ZmhBook b) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ZmhBookPage(book: b)),
    );
    if (mounted) setState(() => _epoch++);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final cs = Theme.of(context).colorScheme;

    if (_first && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_books.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_err != null ? Icons.cloud_off : Icons.inbox_outlined,
                  size: 40, color: cs.outline),
              const SizedBox(height: 10),
              Text(_err ?? '这个榜暂时没有书',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => unawaited(_reload()),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _reload,
      child: CustomScrollView(
        controller: _sc,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 132,
                childAspectRatio: .58,
                crossAxisSpacing: 12,
                mainAxisSpacing: 16,
              ),
              delegate: SliverChildBuilderDelegate(
                (_, i) {
                  final b = _books[i];
                  return MangaCoverCard(
                    title: b.title,
                    sub: b.last.isNotEmpty
                        ? b.last
                        : (b.types.isEmpty ? '再漫画' : b.types),
                    coverUrl: b.coverUrl,
                    imageKey: '$_epoch',
                    bustCache: true,
                    memWidth: 320,
                    onTap: () => _open(b),
                  );
                },
                childCount: _books.length,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24, top: 8),
              child: Center(child: _footer(cs)),
            ),
          ),
        ],
      ),
    );
  }

  /// 列表底下那行。中途失败不自己重试（一直滑到底会连发请求），
  /// 给一个按钮，人点一下才再来。
  Widget _footer(ColorScheme cs) {
    if (_err != null) {
      return TextButton(
        onPressed: () {
          setState(() {
            _err = null;
            _done = false;
          });
          unawaited(_loadMore());
        },
        child: const Text('取不到，重试', style: TextStyle(fontSize: 12)),
      );
    }
    if (_loading) {
      return SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: cs.outline),
      );
    }
    if (_done) {
      return Text('到底了', style: TextStyle(fontSize: 12, color: cs.outline));
    }
    return const SizedBox(height: 18);
  }
}
