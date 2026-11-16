import 'dart:async';

import 'package:flutter/material.dart';

import '../manga.dart';
import '../pages/manga_detail_page.dart';
import 'empty_view.dart';
import 'retry_image.dart';

/// 内部书源的书，一行一本。
///
/// 版式照「我的-回收站」那一套来：RefreshIndicator 包一层 ListView，
/// 每一行是 ListTile（左边封面、中间书名、右边热度）。之前漫画这边是
/// 网格铺封面，翻到第几本全靠眼睛数，一百多本以后就找不着北了。
///
/// 翻页还是滑到底续取，一页 40 本——两三个人名一屏，正好。
class MangaShelfList extends StatefulWidget {
  /// hot / recent / title / progress，后端只认这几个。
  final String sort;

  /// 状态筛选，空串 = 全部。
  final String status;

  /// 点作者进来时带它；和 [tag] 二选一，也能一起用。
  final String author;
  final String tag;

  final String emptyTitle;
  final String emptyHint;
  final IconData emptyIcon;

  /// 右边那列热度。作者/标签结果页也用它，热度还是个有用的线索。
  final bool showHot;

  const MangaShelfList({
    super.key,
    this.sort = 'hot',
    this.status = '',
    this.author = '',
    this.tag = '',
    this.emptyTitle = '这里还没有书',
    this.emptyHint = '',
    this.emptyIcon = Icons.menu_book_outlined,
    this.showHot = true,
  });

  @override
  State<MangaShelfList> createState() => _MangaShelfListState();
}

class _MangaShelfListState extends State<MangaShelfList>
    with AutomaticKeepAliveClientMixin {
  static const _pageSize = 40;

  final ScrollController _sc = ScrollController();
  final List<MangaBook> _books = [];
  int _total = 0;
  bool _first = true;
  bool _loadingMore = false;
  String? _err;

  /// 从详情页回来 +1：CanvasKit 会回收看不见的封面纹理，
  /// ImageCache 还记着「已解码」，不换 key 回来就是一排黑块。
  int _epoch = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _sc.addListener(_onScroll);
    unawaited(_reload());
  }

  @override
  void dispose() {
    _sc.removeListener(_onScroll);
    _sc.dispose();
    super.dispose();
  }

  bool get _hasMore => _books.length < _total;

  void _onScroll() {
    if (!_sc.hasClients || _loadingMore || _first) return;
    if (!_hasMore) return;
    if (_sc.position.extentAfter < 600) unawaited(_loadMore());
  }

  Future<MangaShelfPage> _fetch(int offset) => MangaApi.shelf(
        offset: offset,
        limit: _pageSize,
        sort: widget.sort,
        status: widget.status,
        author: widget.author,
        tag: widget.tag,
      );

  Future<void> _reload() async {
    setState(() {
      _first = true;
      _err = null;
    });
    try {
      final page = await _fetch(0);
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

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _fetch(_books.length);
      if (!mounted) return;
      setState(() {
        // 抓取那边可能刚插了书把顺序挤一下，重复的按 id 剔掉
        final have = {for (final b in _books) b.id};
        _books.addAll(page.books.where((b) => !have.contains(b.id)));
        _total = page.total;
        _loadingMore = false;
      });
      _maybeFill();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  /// 一屏没铺满时滚不动，也就没人叫 _loadMore，得自己催一下。
  void _maybeFill() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_sc.hasClients) return;
      if (_hasMore && !_loadingMore && _sc.position.extentAfter < 400) {
        unawaited(_loadMore());
      }
    });
  }

  Future<void> _open(MangaBook b) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MangaDetailPage(book: b)),
    );
    if (mounted) setState(() => _epoch++);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final cs = Theme.of(context).colorScheme;

    if (_first) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_books.isEmpty) {
      if (_err != null) {
        return EmptyView(
          icon: Icons.cloud_off,
          title: '取不到',
          hint: _err,
          error: true,
          action: TextButton(onPressed: _reload, child: const Text('重试')),
        ).scrollable();
      }
      return EmptyView(
        icon: widget.emptyIcon,
        title: widget.emptyTitle,
        hint: widget.emptyHint,
      ).scrollable();
    }

    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.builder(
        controller: _sc,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: _books.length + 1,
        itemBuilder: (context, i) {
          if (i == _books.length) return _footer(cs);
          final b = _books[i];
          return _row(b);
        },
      ),
    );
  }

  Widget _row(MangaBook b) {
    final cs = Theme.of(context).colorScheme;
    final sub = <String>[
      if (b.authors.isNotEmpty) b.authors,
      if (b.chapterCount > 0) '${b.chapterCount} 话',
    ].join(' · ');

    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      leading: SizedBox(
        width: 44,
        height: 60,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: b.coverUrl.isEmpty
              ? Container(
                  color: cs.surfaceContainerHighest,
                  child: Icon(Icons.menu_book, size: 18, color: cs.outline),
                )
              : RetryImage(
                  key: ValueKey('${b.coverUrl}#$_epoch'),
                  url: b.coverUrl,
                  fit: BoxFit.cover,
                  memCacheWidth: 132,
                  probeSize: false,
                ),
        ),
      ),
      title: Text(
        b.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        sub,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: cs.outline),
      ),
      trailing: widget.showHot && b.hot > 0
          ? Text(
              hotText(b.hot),
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            )
          : null,
      onTap: () => _open(b),
    );
  }

  Widget _footer(ColorScheme cs) {
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (!_hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text('$_total 本，到底了',
              style: TextStyle(fontSize: 12, color: cs.outline)),
        ),
      );
    }
    return const SizedBox(height: 48);
  }
}
