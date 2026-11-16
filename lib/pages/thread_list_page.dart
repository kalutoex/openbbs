import 'package:flutter/material.dart';

import '../api.dart';
import '../manga.dart';
import '../manga_source.dart';
import '../manga_user.dart';
import '../paged.dart';
import '../zmh.dart';
import '../widgets/empty_view.dart';
import '../widgets/page_width.dart';
import '../widgets/retry_image.dart';
import '../widgets/thread_tile.dart';
import 'manga_detail_page.dart';
import 'source_book_page.dart';
import 'zmh_book_page.dart';
import 'thread_page.dart';

import '../l10n/error_text.dart';
import '../l10n/l10n.dart';

/// 这一页顶上要不要带一节漫画。收藏页带收藏的，历史页带看过的。
enum MangaSection { none, favs, history }

/// 一条只有帖子列表的页：收藏、浏览历史共用。
///
/// 漫画不在帖子列表里，但阿尔要在这两处看得见漫画，所以在顶上拼一节。
/// 数据走 /manga/favs、/manga/history，和帖子那套各算各的。
class ThreadListPage extends StatefulWidget {
  final String title;
  final String path;
  final String emptyText;
  final MangaSection manga;

  const ThreadListPage({
    super.key,
    required this.title,
    required this.path,
    required this.emptyText,
    this.manga = MangaSection.none,
  });

  @override
  State<ThreadListPage> createState() => _ThreadListPageState();
}

class _ThreadListPageState extends State<ThreadListPage> {
  final ScrollController _scroll = ScrollController();

  /// 顶上那一节漫画。null = 还在取。
  List<MangaFav>? _favs;
  List<MangaHist>? _hist;

  late final Pager<Map<String, dynamic>> _pager = Pager(
    fetch: (page) async {
      final d = await Api.get(widget.path, query: {'page': '$page'});
      return PageSlice((d['items'] as List).cast<Map<String, dynamic>>());
    },
  );

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - _ahead) {
        _load();
      }
    });
    // 第一页必须走 reset：more() 不动 first，拿它开头就永远转圈。
    _pager.reset().then((_) {
      if (mounted) setState(() {});
    });
    _loadManga();
  }

  bool get _wantManga => widget.manga != MangaSection.none;

  Future<void> _loadManga() async {
    if (!_wantManga) return;
    try {
      if (widget.manga == MangaSection.favs) {
        final list = await MangaUserApi.favs();
        if (mounted) setState(() => _favs = list);
      } else {
        final list = await MangaUserApi.hist();
        if (mounted) setState(() => _hist = list);
      }
    } catch (_) {
      // 漫画这节取不到就当没有，不连累帖子列表。
      if (!mounted) return;
      setState(() {
        if (widget.manga == MangaSection.favs) {
          _favs = const [];
        } else {
          _hist = const [];
        }
      });
    }
  }

  int get _mangaCount =>
      widget.manga == MangaSection.favs ? (_favs?.length ?? 0) : (_hist?.length ?? 0);

  /// 离底还有一屏就开始拉下一页，滑到底时内容已经在手上了。
  double get _ahead {
    final vp = _scroll.hasClients ? _scroll.position.viewportDimension : 0.0;
    return vp > 0 ? vp : 400;
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {});
    await Future.wait([_pager.reset(), _loadManga()]);
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    await _pager.more();
    if (mounted) setState(() {});
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

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
            tooltip: Lc.current.refresh,
          ),
        ],
      ),
      body: PageWidth(
        child: RefreshIndicator(onRefresh: _reload, child: _body(context, cs)),
      ),
    );
  }

  Widget _body(BuildContext context, ColorScheme cs) {
    final hasManga = _mangaCount > 0;

    // 帖子还在拉、漫画已经有了：先把漫画那节显示出来，别让人对着转圈看。
    if (_pager.first && !hasManga) {
      return const Center(child: CircularProgressIndicator());
    }

    final err = _pager.error;
    if (err != null && _pager.isEmpty && !hasManga) {
      return EmptyView(
        icon: Icons.cloud_off_rounded,
        title: Lc.current.loadFailed,
        hint: errorText(context, err),
        error: true,
        action: FilledButton.tonal(
          onPressed: _reload,
          child: Text(Lc.current.retry),
        ),
      ).scrollable();
    }

    if (_pager.isEmpty && !hasManga) {
      return EmptyView(
        icon: Icons.inbox_outlined,
        title: widget.emptyText,
      ).scrollable();
    }

    final head = hasManga ? 1 : 0;
    final n = _pager.items.length;

    return ListView.builder(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: head + n + 1,
      itemBuilder: (context, i) {
        if (i < head) return _mangaHead(cs);
        final k = i - head;
        if (k == n) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: Text(
                _pager.busy
                    ? Lc.current.loading
                    : (_pager.hasMore
                          ? Lc.current.moreToLoad
                          : Lc.current.endOfList),
                style: TextStyle(color: cs.outline, fontSize: 12),
              ),
            ),
          );
        }
        final it = _pager.items[k];
        return ThreadTile(item: it, onTap: () => _open(it), onDeleted: _reload);
      },
    );
  }

  /// 顶上的漫画一排。收藏和历史共用一套卡片，差别只在底下那行字。
  Widget _mangaHead(ColorScheme cs) {
    final tt = Theme.of(context).textTheme;
    final favs = _favs ?? const <MangaFav>[];
    final hist = _hist ?? const <MangaHist>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Row(
            children: [
              Text('漫画', style: tt.titleSmall),
              const SizedBox(width: 6),
              Text('$_mangaCount',
                  style: TextStyle(fontSize: 12, color: cs.outline)),
            ],
          ),
        ),
        SizedBox(
          height: 168,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _mangaCount,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              if (widget.manga == MangaSection.favs) {
                final f = favs[i];
                return _mangaCell(
                  title: f.title,
                  sub: f.isSource ? '书源' : '本地',
                  coverUrl: f.coverUrl,
                  hasNew: f.hasNew,
                  onTap: () => _openManga(
                    kind: f.kind,
                    ref: f.ref,
                    sourceId: f.sourceId,
                    title: f.title,
                    author: f.author,
                    cover: f.cover,
                  ),
                );
              }
              final h = hist[i];
              return _mangaCell(
                title: h.title,
                sub: h.where.isEmpty
                    ? (h.isSource ? '书源' : '本地')
                    : h.where,
                coverUrl: h.coverUrl,
                onTap: () => _openManga(
                  kind: h.kind,
                  ref: h.ref,
                  sourceId: h.sourceId,
                  title: h.title,
                  author: h.author,
                  cover: h.cover,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Divider(height: 1, color: cs.outlineVariant.withValues(alpha: .4)),
      ],
    );
  }

  Widget _mangaCell({
    required String title,
    required String sub,
    required String coverUrl,
    required VoidCallback onTap,
    bool hasNew = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return SizedBox(
      width: 92,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 122,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: coverUrl.isEmpty
                          ? Container(
                              color: cs.surfaceContainerHighest,
                              child: Icon(Icons.menu_book, color: cs.outline),
                            )
                          : RetryImage(
                              url: coverUrl,
                              fit: BoxFit.cover,
                              memCacheWidth: 240,
                              probeSize: false,
                            ),
                    ),
                    if (hasNew)
                      Positioned(
                        top: 5,
                        right: 5,
                        child: Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: cs.error,
                            shape: BoxShape.circle,
                            border: Border.all(color: cs.surface, width: 1.2),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
            Text(sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, color: cs.outline)),
          ],
        ),
      ),
    );
  }

  /// 点开一本：本地进书架那套详情，书源进源站那套。
  Future<void> _openManga({
    required String kind,
    required String ref,
    required int sourceId,
    required String title,
    required String author,
    required String cover,
  }) async {
    if (kind == 'zmh') {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ZmhBookPage(
            book: ZmhBook(
              id: int.tryParse(ref) ?? 0,
              title: title,
              authors: author,
              cover: cover,
            ),
          ),
        ),
      );
    } else if (kind == 'source') {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SourceBookPage(
            book: SourceBook(
              sourceId: sourceId,
              sourceName: '',
              name: title,
              author: author,
              cover: cover,
              url: ref,
            ),
          ),
        ),
      );
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MangaDetailPage(
            book: MangaBook(
              id: '',
              dir: ref,
              title: title,
              authors: author,
              types: '',
              status: '',
              desc: '',
              cover: cover,
              chapterCount: 0,
              lastChapter: '',
            ),
          ),
        ),
      );
    }
    if (!mounted) return;
    // 回来时进度、收藏都可能变了。
    await _loadManga();
  }
}
