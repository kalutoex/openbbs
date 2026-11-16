import 'dart:async';

import 'package:flutter/material.dart';

import '../manga.dart';
import '../widgets/manga_card.dart';
import '../widgets/retry_image.dart';
import '../widgets/page_width.dart';
import 'manga_detail_page.dart';
import 'manga_rank_page.dart';

import '../l10n/l10n.dart';

/// 内部书源：本地已经抓下来的漫画，网格铺封面。
///
/// 数据来自后端扫目录，抓取任务是另一个进程在跑，所以这里随时可能变多——
/// 下拉刷新即可，不用重启 App。
///
/// 2026-11 起只留一个书源（就是这个库），外部书源那套入口全下线了：
/// 所以顶上只有一个搜索框，搜的永远是这批书。
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

  /// 正在按新的排序/筛选重拉第一页。清空列表到结果回来之间，
  /// 界面该转圈而不是显示「没找到」。
  bool _filtering = false;
  String? _err;

  /// 从详情页回来时 +1。CanvasKit 会把不在当前页的图片纹理回收掉，
  /// 而 ImageCache 里还留着「已解码」的记录——结果就是一整片黑块。
  /// 换个 key 让封面重新走一遍解码，纹理就回来了。
  int _epoch = 0;

  /// 顶上推荐那一排：就是内部书源里热度最高的十几本，点开直接看。
  /// null = 还在取；取不到就是空列表，书库照常显示，不为推荐位红一片。
  List<MangaBook>? _recs;

  /// 排序：hot / recent / title / progress。后端只认这几个。
  /// hot 是默认——书是按人气榜下的，按名字排出来的顺序没意义。
  String _sort = 'hot';

  /// 状态筛选，空串 = 全部。
  String _status = '';

  /// 书库内搜索词，空串 = 不筛。搜书名、作者、标签。
  String _q = '';
  bool _searchOpen = false;
  final TextEditingController _searchCtl = TextEditingController();
  Timer? _searchDebounce;

  static const _sorts = <(String, String, IconData)>[
    ('hot', '热度', Icons.local_fire_department_outlined),
    ('recent', '最近更新', Icons.update),
    ('title', '书名', Icons.sort_by_alpha),
    ('progress', '阅读进度', Icons.bookmark_outline),
  ];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _sc.addListener(_onScroll);
    unawaited(_reload());
    unawaited(_loadRecs());
    mangaBump.addListener(_onBump);
  }

  @override
  void dispose() {
    _sc.removeListener(_onScroll);
    _sc.dispose();
    _searchDebounce?.cancel();
    _searchCtl.dispose();
    mangaBump.removeListener(_onBump);
    super.dispose();
  }

  void _openSearch() {
    setState(() => _searchOpen = true);
  }

  void _closeSearch() {
    _searchDebounce?.cancel();
    _searchCtl.clear();
    final had = _q.isNotEmpty;
    setState(() {
      _searchOpen = false;
      _q = '';
    });
    if (had) unawaited(_applyFilter(recs: false));
  }

  void _onQuery(String v) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      final key = v.trim();
      if (key == _q) return;
      _q = key;
      unawaited(_applyFilter(recs: false));
    });
  }

  /// 排序 / 筛选 / 搜索变了：页码归零，回到顶部重新拉第一页。
  Future<void> _applyFilter({bool recs = false}) async {
    setState(() {
      _books.clear();
      _total = 0;
      _first = true;
      _filtering = true;
      _err = null;
    });
    if (_sc.hasClients) _sc.jumpTo(0);
    await _reload(withRecs: recs);
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

  /// 推荐位固定按热度取，不跟着排序走——它就是「大家都在看」那一排。
  Future<void> _loadRecs() async {
    try {
      final page = await MangaApi.shelf(offset: 0, limit: 18, sort: 'hot');
      if (mounted) setState(() => _recs = page.books);
    } catch (_) {
      if (mounted) setState(() => _recs = const []);
    }
  }

  Future<void> _reload({bool withRecs = true}) async {
    if (withRecs) unawaited(_loadRecs());
    try {
      final page = await MangaApi.shelf(
        offset: 0,
        limit: _pageSize,
        sort: _sort,
        status: _status,
        q: _q,
      );
      if (!mounted) return;
      setState(() {
        _books
          ..clear()
          ..addAll(page.books);
        _total = page.total;
        _first = false;
        _filtering = false;
        _err = null;
      });
      _maybeFill();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _first = false;
        _filtering = false;
        _err = '$e';
      });
    }
  }

  /// 已经翻出来的这一截重新拉一遍，页数不变。
  Future<void> _refreshLoaded() async {
    final want = _books.length < _pageSize ? _pageSize : _books.length;
    try {
      final page = await MangaApi.shelf(
        offset: 0,
        limit: want,
        sort: _sort,
        status: _status,
        q: _q,
      );
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
      final page = await MangaApi.shelf(
        offset: _books.length,
        limit: _pageSize,
        sort: _sort,
        status: _status,
        q: _q,
      );
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

  /// 排序换一种。用底部弹层而不是 PopupMenuButton：
  /// 之前那个小菜单贴在上巴右上角，三项挤成一条，还看不出当前选的是哪个。
  Future<void> _pickSort() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                child: Text('排序方式',
                    style: TextStyle(fontSize: 13, color: cs.outline)),
              ),
              for (final s in _sorts)
                ListTile(
                  leading: Icon(s.$3, size: 20),
                  title: Text(s.$2),
                  trailing: s.$1 == _sort
                      ? Icon(Icons.check, size: 20, color: cs.primary)
                      : null,
                  onTap: () => Navigator.pop(ctx, s.$1),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (picked == null || picked == _sort) return;
    setState(() => _sort = picked);
    await _applyFilter(recs: false);
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
        title: _searchOpen
            ? TextField(
                controller: _searchCtl,
                autofocus: true,
                style: const TextStyle(fontSize: 15),
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: '搜书名 / 作者 / 标签',
                  border: InputBorder.none,
                  isDense: true,
                ),
                onChanged: _onQuery,
                onSubmitted: _onQuery,
              )
            : Text('漫画', style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        actions: _searchOpen
            ? [
                IconButton(
                  onPressed: _closeSearch,
                  icon: const Icon(Icons.close),
                  tooltip: '关闭搜索',
                ),
              ]
            : [
                IconButton(
                  onPressed: _openSearch,
                  icon: const Icon(Icons.search),
                  tooltip: '搜索',
                ),
                IconButton(
                  onPressed: _pickSort,
                  icon: const Icon(Icons.sort),
                  tooltip: '排序',
                ),
              ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _reload(),
        child: PageWidth(
          max: 1100,
          child: _first && _recs == null
              ? const Center(child: CircularProgressIndicator())
              : _scrollBody(cs),
        ),
      ),
    );
  }

  /// 一屏从上到下：推荐、书库、加载更多。
  ///
  /// 全都是 sliver，滚动条只有一条——推荐那一排要是单独一个 ListView
  /// 塞在 Column 里，下拉刷新就只作用在上面那一半。
  Widget _scrollBody(ColorScheme cs) {
    final recs = _recs ?? const <MangaBook>[];
    final showRecs = recs.isNotEmpty && _q.isEmpty && !_searchOpen;
    return CustomScrollView(
      controller: _sc,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        if (showRecs) SliverToBoxAdapter(child: _recRow(cs, recs)),
        SliverToBoxAdapter(child: _shelfHeader(cs)),
        if (_books.isEmpty)
          SliverToBoxAdapter(child: _emptyShelf(cs))
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
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
    );
  }

  Widget _shelfHeader(ColorScheme cs) {
    final filtering = _status.isNotEmpty || _q.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('内部书源', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  _q.isEmpty ? '$_total 本' : '$_total 本 · 「$_q」',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: cs.outline),
                ),
              ),
              if (filtering)
                TextButton(
                  onPressed: () {
                    _searchDebounce?.cancel();
                    _searchCtl.clear();
                    setState(() {
                      _status = '';
                      _q = '';
                      _searchOpen = false;
                    });
                    unawaited(_applyFilter(recs: false));
                  },
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 28),
                  ),
                  child: const Text('清除', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              _statusChip('全部', ''),
              _statusChip('连载中', '连载'),
              _statusChip('已完结', '完结'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String label, String value) {
    final on = _status == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: on,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        onSelected: (_) {
          if (_status == value) return;
          setState(() => _status = value);
          unawaited(_applyFilter(recs: false));
        },
      ),
    );
  }

  Widget _emptyShelf(ColorScheme cs) {
    if (_filtering) {
      return const Padding(
        padding: EdgeInsets.only(top: 48),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    final bad = _err != null;
    final filtered = _q.isNotEmpty || _status.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(top: 40, bottom: 40, left: 24, right: 24),
      child: Center(
        child: Column(
          children: [
            Icon(
                bad
                    ? Icons.cloud_off
                    : (filtered ? Icons.search_off : Icons.menu_book_outlined),
                size: 40,
                color: cs.outline),
            const SizedBox(height: 10),
            Text(
                bad
                    ? '书库取不到'
                    : (filtered ? '没找到' : '书库里还没有书'),
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
            const SizedBox(height: 4),
            Text(
              bad
                  ? _err!
                  : (filtered ? '换个词，或者把筛选清掉' : '抓取那边下完一本，这里就多一本'),
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.outline, fontSize: 12),
            ),
            if (bad) ...[
              const SizedBox(height: 10),
              TextButton(onPressed: () => unawaited(_reload()), child: Text(Lc.current.retry)),
            ],
          ],
        ),
      ),
    );
  }

  /// 推荐那一条横滑。就是书库里热度最高的十几本，封面比格子小一圈。
  Widget _recRow(ColorScheme cs, List<MangaBook> recs) {
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Row(
            children: [
              Text('推荐', style: tt.titleSmall),
              const SizedBox(width: 6),
              Text('按热度 · 点开即看',
                  style: TextStyle(fontSize: 11, color: cs.outline)),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MangaRankPage()),
                ),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 30),
                ),
                child: const Text('更多 ›', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 196,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: recs.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, i) => _recCell(recs[i]),
          ),
        ),
      ],
    );
  }

  Widget _recCell(MangaBook b) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return SizedBox(
      width: 96,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _open(b),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                height: 132,
                child: b.coverUrl.isEmpty
                    ? Container(
                        color: cs.surfaceContainerHighest,
                        child: Icon(Icons.menu_book, color: cs.outline),
                      )
                    : RetryImage(
                        key: ValueKey('${b.coverUrl}#$_epoch'),
                        url: b.coverUrl,
                        fit: BoxFit.cover,
                        memCacheWidth: 260,
                        probeSize: false,
                      ),
              ),
            ),
            const SizedBox(height: 5),
            Text(b.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
            Text(
              b.chapterCount > 0 ? '${b.chapterCount} 话' : '本地',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: cs.outline),
            ),
          ],
        ),
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
    final p = b.progress;
    return MangaCoverCard(
      title: b.title,
      sub: p != null ? p.label : '${b.chapterCount} 话',
      highlight: p != null,
      coverUrl: b.coverUrl,
      imageKey: '$_epoch',
      onTap: () => _open(b),
    );
  }
}
