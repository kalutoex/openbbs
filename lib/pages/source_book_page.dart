import 'dart:async';

import 'package:flutter/material.dart';

import '../manga.dart';
import '../manga_source.dart';
import '../manga_user.dart';
import '../widgets/empty_view.dart';
import '../widgets/page_width.dart';
import '../widgets/retry_image.dart';
import 'manga_reader_page.dart';

/// 书源里的一本书：封面、信息、简介、章节。
///
/// 版式跟本地书架那本详情页一致——同一个人在两套数据之间来回看，
/// 不该有两套操作习惯。差别在底下：这里的章节全在源站，点一下才去取图，
/// 取不到就当页说一句，不装没事。
class SourceBookPage extends StatefulWidget {
  final SourceBook book;

  const SourceBookPage({super.key, required this.book});

  @override
  State<SourceBookPage> createState() => _SourceBookPageState();
}

class _SourceBookPageState extends State<SourceBookPage> {
  SourceBookDetail? _d;
  String? _err;
  bool _descOpen = false;
  bool _asc = false;

  /// 收藏状态，和本地书那页同一套。
  bool _fav = false;
  bool _favBusy = false;

  /// 断点由阅读器自己按 detail.dir 记，这里不用管。

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _err = null);
    try {
      final d = await SourceApi.detail(widget.book.sourceId, widget.book.url);
      final fav = await MangaUserApi.favState('source', widget.book.url);
      if (!mounted) return;
      setState(() {
        _d = d;
        _fav = fav;
      });
      if (fav) unawaited(MangaUserApi.markSeen('source', widget.book.url));
    } catch (e) {
      if (!mounted) return;
      setState(() => _err = '$e');
    }
  }

  /// 阅读器吃的是本地的 MangaDetail，这里把源站的目录套进去——
  /// 只是形状对上了，章节 dir 存的是章节地址，图还是回头问源站。
  MangaDetail _asDetail(SourceBookDetail d) => MangaDetail(
        dir: 'src_${widget.book.sourceId}_${widget.book.url.hashCode}',
        title: d.name.isEmpty ? widget.book.name : d.name,
        authors: d.author,
        types: d.kind,
        status: '',
        desc: d.intro,
        cover: d.cover,
        chapters: d.chapters
            .map((c) => MangaChapter(
                  id: 0,
                  name: c.name,
                  seq: 0,
                  pages: 0,
                  dir: c.url,
                ))
            .toList(),
      );

  /// 按章节对象开，不按下标——列表倒序显示时下标和 d.chapters 是对着反的，
  /// 传下标会点第 3 话翻到倒数第 3 话去。
  Future<void> _open(SourceChapter c) async {
    final d = _d;
    if (d == null) return;
    final i = d.chapters.indexWhere((x) => x.url == c.url);
    if (i < 0) return;
    final sid = widget.book.sourceId;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MangaReaderPage(
          detail: _asDetail(d),
          index: i,
          loader: (ch) => SourceApi.pages(sid, ch.dir),
          readRef: ReadRef.fromSource(widget.book),
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
        kind: 'source',
        ref: widget.book.url,
        sourceId: widget.book.sourceId,
        title: (d?.name.isNotEmpty == true) ? d!.name : widget.book.name,
        author: (d?.author.isNotEmpty == true) ? d!.author : widget.book.author,
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
          (d?.name.isNotEmpty == true ? d!.name : widget.book.name),
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
              title: '这个源取不到',
              hint: _err,
              error: true,
              action: TextButton(onPressed: _load, child: const Text('重试')),
            )
          : d == null
              ? const Center(child: CircularProgressIndicator())
              : _body(d),
    );
  }

  Widget _body(SourceBookDetail d) {
    final cs = Theme.of(context).colorScheme;
    final chs = _asc ? [...d.chapters] : d.chapters.reversed.toList();

    return PageWidth(
      max: 820,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _head(d, chs)),
          if (d.intro.trim().isNotEmpty)
            SliverToBoxAdapter(child: _descBlock(d)),
          SliverToBoxAdapter(child: _chapterHeader(d)),
          if (chs.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '这个源没给出章节。多半是规则对不上，换一个源试试。',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
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

  Widget _cell(SourceChapter c) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _open(c),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: cs.surfaceContainerHighest.withValues(alpha: .6),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.center,
        child: Text(
          c.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: tt.bodySmall,
        ),
      ),
    );
  }

  Widget _chapterHeader(SourceBookDetail d) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          Text('共 ${d.chapters.length} 话',
              style: Theme.of(context).textTheme.titleSmall),
          const Spacer(),
          TextButton.icon(
            onPressed: () => setState(() => _asc = !_asc),
            icon: Icon(
              _asc ? Icons.arrow_downward : Icons.arrow_upward,
              size: 16,
            ),
            label: Text(_asc ? '正序' : '倒序'),
          ),
        ],
      ),
    );
  }

  Widget _descBlock(SourceBookDetail d) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            d.intro.replaceAll(RegExp(r'\s+'), ' ').trim(),
            maxLines: _descOpen ? 30 : 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.55,
              color: cs.onSurfaceVariant,
            ),
          ),
          if (d.intro.length > 90)
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

  Widget _head(SourceBookDetail d, List<SourceChapter> chs) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final n = chs.length;
    final title = d.name.isEmpty ? widget.book.name : d.name;

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
              child: d.coverUrl.isEmpty
                  ? Container(
                      color: cs.surfaceContainerHighest,
                      child: Icon(Icons.menu_book, color: cs.outline),
                    )
                  : RetryImage(
                      url: d.coverUrl,
                      fit: BoxFit.cover,
                      memCacheWidth: 320,
                      probeSize: false,
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
                  style: tt.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700, height: 1.25),
                ),
                const SizedBox(height: 8),
                if (d.author.isNotEmpty)
                  _iconLine(Icons.person_outline, d.author),
                if (d.kind.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _iconLine(Icons.tag, d.kind, color: cs.primary),
                ],
                const SizedBox(height: 6),
                _iconLine(Icons.cloud_outlined, '$n 话 · ${widget.book.sourceName}'),
                if (d.last.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _iconLine(Icons.schedule, d.last),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: n == 0 ? null : () => _open(_asc ? d.chapters.first : d.chapters.last),
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
