import 'dart:async';

import 'package:flutter/material.dart';

import '../manga.dart';
import '../widgets/retry_image.dart';
import '../widgets/empty_view.dart';
import '../widgets/page_width.dart';
import 'manga_detail_page.dart';

import '../l10n/l10n.dart';
/// 书架：本地已经抓下来的漫画，网格铺封面。
///
/// 数据来自后端扫目录，抓取任务是另一个进程在跑，所以这里随时可能变多——
/// 下拉刷新即可，不用重启 App。
class MangaTab extends StatefulWidget {
  final VoidCallback onMenu;

  const MangaTab({super.key, required this.onMenu});

  @override
  State<MangaTab> createState() => _MangaTabState();
}

class _MangaTabState extends State<MangaTab>
    with AutomaticKeepAliveClientMixin {
  /// 一次要一小把。书多了以后一口气全发，光是封面排队下载就够卡的了。
  static const _pageSize = 12;

  final ScrollController _sc = ScrollController();
  final List<MangaBook> _books = [];
  int _total = 0;
  bool _first = true;
  bool _loadingMore = false;
  String? _err;

  /// 从详情页回来时 +1。CanvasKit 会把不在当前页的图片纹理回收掉，
  /// 而 ImageCache 里还留着「已解码」的记录——结果就是一整片黑块。
  /// 换个 key 让封面重新走一遍解码，纹理就回来了。
  int _epoch = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _sc.addListener(_onScroll);
    unawaited(_reload());
    mangaBump.addListener(_onBump);
  }

  @override
  void dispose() {
    _sc.removeListener(_onScroll);
    _sc.dispose();
    mangaBump.removeListener(_onBump);
    super.dispose();
  }

  bool get _hasMore => _books.length < _total;

  void _onScroll() {
    if (!_sc.hasClients || _loadingMore || _first) return;
    if (!_hasMore) return;
    if (_sc.position.extentAfter < 700) unawaited(_loadMore());
  }

  /// 一屏都没铺满的时候滚不动，也就没人叫 _loadMore，得自己催一下。
  void _maybeFill() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_sc.hasClients) return;
      if (_hasMore && !_loadingMore && _sc.position.extentAfter < 400) {
        unawaited(_loadMore());
      }
    });
  }

  /// 抓取任务那边动了（mangaBump）：已经把书翻出来看的这些人不动位置，
  /// 只把手上这一截重新对一遍，省得又从头翻。
  void _onBump() {
    if (_books.isEmpty) {
      unawaited(_reload());
    } else {
      unawaited(_refreshLoaded());
    }
  }

  Future<void> _reload() async {
    try {
      final page = await MangaApi.shelf(offset: 0, limit: _pageSize);
      if (!mounted) return;
      setState(() {
        _books
          ..clear()
          ..addAll(page.books);
        _total = page.total;
        _first = false;
        _err = null;
      });
      _maybeFill();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _first = false;
        _err = '$e';
      });
    }
  }

  /// 已经翻出来的这一截重新拉一遍，页数不变。
  Future<void> _refreshLoaded() async {
    final want = _books.length < _pageSize ? _pageSize : _books.length;
    try {
      final page = await MangaApi.shelf(offset: 0, limit: want);
      if (!mounted) return;
      setState(() {
        _books
          ..clear()
          ..addAll(page.books);
        _total = page.total;
        _err = null;
      });
      _maybeFill();
    } catch (_) {
      // 后台刷新失败就算了，界面上的还看得见。
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await MangaApi.shelf(offset: _books.length, limit: _pageSize);
      if (!mounted) return;
      setState(() {
        // 抓取那边可能刚插了新书把顺序挤了一下，重复的按 id 剔掉。
        final have = {for (final b in _books) b.id};
        _books.addAll(page.books.where((b) => !have.contains(b.id)));
        _total = page.total;
        _loadingMore = false;
      });
      _maybeFill();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: widget.onMenu,
          icon: const Icon(Icons.menu),
          tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
        ),
        titleSpacing: 0,
        title:
            Text('漫画', style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
            tooltip: Lc.current.refresh,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: _first
            ? const Center(child: CircularProgressIndicator())
            : _err != null && _books.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: 120),
                      Icon(Icons.cloud_off, size: 44, color: cs.outline),
                      const SizedBox(height: 12),
                      Center(
                        child: Text(
                          _err!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: TextButton(
                            onPressed: _reload, child: Text(Lc.current.retry)),
                      ),
                    ],
                  )
                : _books.isEmpty
                    ? ListView(
                        children: const [
                          SizedBox(height: 90),
                          EmptyView(
                            icon: Icons.menu_book_outlined,
                            title: '书架还是空的',
                            hint: '抓取任务在后台跑，过会儿下拉刷新',
                          ),
                        ],
                      )
                    : _grid(),
      ),
    );
  }

  Widget _grid() {
    return PageWidth(
      max: 1100,
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
                (_, i) => _cell(_books[i]),
                childCount: _books.length,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: _hasMore ? 56 : 24,
              child: _hasMore
                  ? const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _open(MangaBook b) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MangaDetailPage(book: b)),
    );
    if (!mounted) return;
    // 回来只重解纹理，不重新拉数据——手上这一截还是对的。
    setState(() => _epoch++);
  }

  Widget _cell(MangaBook b) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _open(b),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: b.coverUrl.isEmpty
                  ? Container(
                      color: cs.surfaceContainerHighest,
                      child: Icon(Icons.menu_book, color: cs.outline),
                    )
                  : RetryImage(
                      key: ValueKey('${b.coverUrl}#$_epoch'),
                      url: b.coverUrl,
                      fit: BoxFit.cover,
                      memCacheWidth: 320,
                      probeSize: false,
                    ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            b.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          Text(
            '${b.chapterCount} 话',
            style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
