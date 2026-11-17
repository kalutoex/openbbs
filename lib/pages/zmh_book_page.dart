import 'dart:async';

import 'package:flutter/material.dart';

import '../manga.dart';
import '../manga_user.dart';
import '../widgets/empty_view.dart';
import '../widgets/page_width.dart';
import '../widgets/retry_image.dart';
import '../zmh.dart';
import 'manga_reader_page.dart';

/// 再漫画的一本书：点开就看不下载。
///
/// 版式跟本地书架、书源那两套详情页一致——同一个人在三套数据之间来回看，
/// 操作习惯不该有第三种。区别只有一处：这里的章节是服务端现取的，
/// 图片也是现取的，所以慢一点、断一点都是正常的。
class ZmhBookPage extends StatefulWidget {
  final ZmhBook book;

  const ZmhBookPage({super.key, required this.book});

  @override
  State<ZmhBookPage> createState() => _ZmhBookPageState();
}

class _ZmhBookPageState extends State<ZmhBookPage> {
  ZmhDetail? _d;
  String? _err;
  bool _descOpen = false;
  bool _asc = false;
  bool _fav = false;
  bool _favBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _err = null);
    try {
      final d = await ZmhApi.detail(widget.book.id);
      final fav = await MangaUserApi.favState('zmh', '${widget.book.id}');
      if (!mounted) return;
      setState(() {
        _d = d;
        _fav = fav;
      });
      // 收藏着的连载点开了 = 新话看见了，让服务端把追更基线推上去。
      if (fav) unawaited(MangaUserApi.markSeen('zmh', '${widget.book.id}'));
    } catch (e) {
      if (!mounted) return;
      setState(() => _err = '$e');
    }
  }

  /// 阅读器吃 MangaDetail，章节 dir 放章节 id。
  MangaDetail _asDetail(ZmhDetail d) => MangaDetail(
        dir: 'zmh_${d.id}',
        title: d.title.isEmpty ? widget.book.title : d.title,
        authors: d.authors,
        types: d.types,
        status: d.status,
        desc: d.desc,
        cover: d.cover,
        chapters: d.chapters
            .map((c) => MangaChapter(
                  id: c.id,
                  name: c.name,
                  seq: c.order,
                  pages: 0,
                  dir: '${c.id}',
                ))
            .toList(),
      );

  Future<void> _open(ZmhChapter c) async {
    final d = _d;
    if (d == null) return;
    final i = d.chapters.indexWhere((x) => x.id == c.id);
    if (i < 0) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MangaReaderPage(
          detail: _asDetail(d),
          index: i,
          loader: (_) => ZmhApi.pages(d.id, c.id),
          readRef: ReadRef(
            kind: 'zmh',
            ref: '${d.id}',
            title: d.title.isEmpty ? widget.book.title : d.title,
            author: d.authors,
            cover: d.cover,
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _toggleFav() async {
    if (_favBusy) return;
    final d = _d;
    setState(() => _favBusy = true);
    try {
      final on = await MangaUserApi.toggleFav(
        kind: 'zmh',
        ref: '${widget.book.id}',
        title: (d?.title.isNotEmpty == true) ? d!.title : widget.book.title,
        author: (d?.authors.isNotEmpty == true)
            ? d!.authors
            : widget.book.authors,
        cover: (d?.cover.isNotEmpty == true) ? d!.cover : widget.book.cover,
      );
      if (!mounted) return;
      setState(() => _fav = on);
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text(on ? '已收藏' : '已取消收藏'),
          duration: const Duration(seconds: 1),
        ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _favBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          (d != null && d.title.isNotEmpty) ? d.title : widget.book.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            onPressed: _toggleFav,
            icon: Icon(_fav ? Icons.favorite : Icons.favorite_border),
            color: _fav ? Theme.of(context).colorScheme.error : null,
            tooltip: _fav ? '取消收藏' : '收藏',
          ),
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            tooltip: '重新取',
          ),
        ],
      ),
      body: _err != null
          ? EmptyView(
              icon: Icons.cloud_off,
              title: '这本取不到',
              hint: _err,
              error: true,
              action: TextButton(onPressed: _load, child: const Text('重试')),
            )
          : d == null
              ? const Center(child: CircularProgressIndicator())
              : _body(d),
    );
  }

  Widget _body(ZmhDetail d) {
    final cs = Theme.of(context).colorScheme;
    final chs = _asc ? d.chapters : d.chapters.reversed.toList();

    return PageWidth(
      max: 820,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _head(d, chs)),
          if (d.desc.trim().isNotEmpty)
            SliverToBoxAdapter(child: _descBlock(d)),
          SliverToBoxAdapter(child: _chapterHeader(d)),
          if (chs.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('这本没给出章节。',
                    style: TextStyle(color: cs.onSurfaceVariant)),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  mainAxisExtent: 38,
                ),
                delegate: SliverChildBuilderDelegate(
                  (_, i) => _cell(chs[i]),
                  childCount: chs.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _cell(ZmhChapter c) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: c.fee ? null : () => _open(c),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: cs.surfaceContainerHighest.withValues(alpha: c.fee ? .25 : .6),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.center,
        child: Text(
          c.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: tt.bodySmall?.copyWith(
              color: c.fee ? cs.outline : null),
        ),
      ),
    );
  }

  Widget _chapterHeader(ZmhDetail d) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          Text('共 ${d.chapters.length} 话',
              style: Theme.of(context).textTheme.titleSmall),
          const Spacer(),
          TextButton.icon(
            onPressed: () => setState(() => _asc = !_asc),
            icon: Icon(_asc ? Icons.arrow_downward : Icons.arrow_upward,
                size: 16),
            label: Text(_asc ? '正序' : '倒序'),
          ),
        ],
      ),
    );
  }

  Widget _descBlock(ZmhDetail d) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            d.desc.replaceAll(RegExp(r'\s+'), ' ').trim(),
            maxLines: _descOpen ? 30 : 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 12.5, height: 1.55, color: cs.onSurfaceVariant),
          ),
          if (d.desc.length > 90)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => setState(() => _descOpen = !_descOpen),
                child: Text(_descOpen ? '收起' : '展开'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _head(ZmhDetail d, List<ZmhChapter> chs) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final n = chs.length;
    final title = d.title.isEmpty ? widget.book.title : d.title;
    final cover =
        d.coverThumb.isEmpty ? widget.book.coverThumb : d.coverThumb;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [cs.primary.withValues(alpha: .10), cs.surface],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 108,
              height: 148,
              child: cover.isEmpty
                  ? Container(
                      color: cs.surfaceContainerHighest,
                      child: Icon(Icons.menu_book, color: cs.outline),
                    )
                  : RetryImage(
                      url: cover,
                      fit: BoxFit.cover,
                      memCacheWidth: 320,
                      probeSize: false,
                      bustCache: true,
                    ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: tt.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700, height: 1.25),
                ),
                const SizedBox(height: 8),
                if (d.authors.isNotEmpty)
                  _iconLine(Icons.person_outline, d.authors),
                if (d.types.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _iconLine(Icons.tag, d.types, color: cs.primary),
                ],
                const SizedBox(height: 6),
                _iconLine(Icons.cloud_outlined,
                    '$n 话 · 再漫画${d.status.isEmpty ? '' : ' · ${d.status}'}'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: n == 0
                            ? null
                            : () => _open(
                                _asc ? d.chapters.first : d.chapters.last),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 38),
                          padding: EdgeInsets.zero,
                        ),
                        child: Text(
                          _asc ? '从头看' : '看最新',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconLine(IconData ic, String text, {Color? color}) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(ic, size: 14, color: color ?? cs.onSurfaceVariant),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: color ?? cs.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
