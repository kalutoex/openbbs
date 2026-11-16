import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../manga.dart';
import '../manga_user.dart';
import '../read_pos.dart';
import '../widgets/retry_image.dart';
import '../widgets/empty_view.dart';
import '../widgets/page_width.dart';
import 'manga_filter_page.dart';
import 'manga_reader_page.dart';

import '../l10n/l10n.dart';
/// 一本书的详情：封面、信息、简介、章节格子。
///
/// 版式照着大家习惯的漫画 App 来——封面在左、信息在右、按钮就在手边，
/// 简介下面直接是章节格子，四列排开，一屏能扫到十几个话数。
///
/// 章节默认倒序（最新在上），右边可以切换成正序。看过的位置从阅读页
/// 存的那条 `manga_pos_<书目录>` 里读，主按钮直接续到那一话。
class MangaDetailPage extends StatefulWidget {
  final MangaBook book;

  const MangaDetailPage({super.key, required this.book});

  @override
  State<MangaDetailPage> createState() => _MangaDetailPageState();
}

class _MangaDetailPageState extends State<MangaDetailPage> {
  MangaDetail? _d;
  String? _err;
  bool _descOpen = false;
  bool _asc = false;

  /// 上次读到的话（章节目录名）和页码，没有就是空。
  String _posCh = '';
  int _posPage = 0;

  /// 收藏状态。先按「没收藏」画，查到是收藏中的再点亮，
  /// 免得每次进详情都先闪一下空心的心。
  bool _fav = false;
  bool _favBusy = false;

  /// 本机的阅读位置。key 带「站 + 人」，换号不会串到别人的进度上。
  String get _posKey => mangaPosKey(widget.book.dir);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await MangaApi.detail(widget.book.dir);
      String ch = '';
      var page = 0;
      try {
        final sp = await SharedPreferences.getInstance();
        // 老 key 只在新的空着时兜一次，读到就按新 key 存回去
        var raw = sp.getString(_posKey);
        raw ??= sp.getString(mangaLegacyPosKey(widget.book.dir));
        if (raw != null && raw.contains('|')) {
          final cut = raw.lastIndexOf('|');
          ch = raw.substring(0, cut);
          page = int.tryParse(raw.substring(cut + 1)) ?? 0;
        }
      } catch (_) {}
      // 本机没记过位置就接账号上的那条：换设备登录时靠它续上，
      // 而不是让人从第一话重新翻。
      final remote = d.progress;
      if (ch.isEmpty && remote != null && remote.chapterRef.isNotEmpty) {
        ch = remote.chapterRef;
        page = remote.page;
      }
      final fav = await MangaUserApi.favState('local', widget.book.dir);
      if (!mounted) return;
      setState(() {
        _d = d;
        _err = null;
        _posCh = ch;
        _posPage = page;
        _fav = fav;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _err = '$e');
    }
  }

  void _open(int i) {
    final d = _d;
    if (d == null || i < 0 || i >= d.chapters.length) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MangaReaderPage(
          detail: d,
          index: i,
          readRef: ReadRef.fromBook(widget.book),
        ),
      ),
    ).then((_) => _load());
  }

  /// 点一下收藏 / 取消。等接口回来再变图标，中途连点会被 _favBusy 挡住。
  Future<void> _toggleFav() async {
    if (_favBusy) return;
    final d = _d;
    setState(() => _favBusy = true);
    try {
      final on = await MangaUserApi.toggleFav(
        kind: 'local',
        ref: widget.book.dir,
        title: d?.title ?? widget.book.title,
        author: d?.authors ?? widget.book.authors,
        cover: d?.cover.isNotEmpty == true ? d!.cover : widget.book.cover,
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

  /// 上次读到的那一话在 chapters 里的下标，没读过就是 -1。
  int get _posIndex {
    final d = _d;
    if (d == null || _posCh.isEmpty) return -1;
    for (var i = 0; i < d.chapters.length; i++) {
      if (d.chapters[i].dir == _posCh) return i;
    }
    return -1;
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          d?.title ?? widget.book.title,
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
        ],
      ),
      body: _err != null
          ? EmptyView(
              icon: Icons.cloud_off,
              title: '取不到这本书',
              hint: _err,
              error: true,
              action: TextButton(onPressed: _load, child: Text(Lc.current.retry)),
            )
          : d == null
              ? const Center(child: CircularProgressIndicator())
              : _body(d),
    );
  }

  Widget _body(MangaDetail d) {
    final cs = Theme.of(context).colorScheme;
    final chs = _asc
        ? [...d.chapters]
        : d.chapters.reversed.toList();

    return PageWidth(
      max: 820,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          _head(d),
          if (d.desc.trim().isNotEmpty) _descBlock(d),
          const SizedBox(height: 20),
          _chapterHeader(d),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                mainAxisExtent: 38,
              ),
              itemCount: chs.length,
              itemBuilder: (_, i) => _cell(d, chs[i]),
            ),
          ),
          if (chs.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('还没有下载任何一话',
                  style: TextStyle(color: cs.onSurfaceVariant)),
            ),
        ],
      ),
    );
  }

  Widget _head(MangaDetail d) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final n = d.chapters.length;
    final pi = _posIndex;

    // 作者和标签拆成一个个小胶囊：以前是一整行死字，点了没反应。
    final authors = d.authors
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final tags = d.types
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            cs.primary.withValues(alpha: .10),
            cs.surface,
          ],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cover(d),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  d.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: tt.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700, height: 1.25),
                ),
                const SizedBox(height: 8),
                if (authors.isNotEmpty || tags.isNotEmpty) ...[
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final a in authors) _chip(a, author: true),
                      for (final t in tags) _chip(t, author: false),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                _iconLine(Icons.schedule, '$n 话已下载'),
                if (d.hot > 0) ...[
                  const SizedBox(height: 4),
                  _iconLine(Icons.local_fire_department_outlined,
                      '热度 ${hotText(d.hot)}'),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: n == 0
                            ? null
                            : () => _open(pi >= 0 ? pi : 0),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 38),
                          padding: EdgeInsets.zero,
                        ),
                        child: Text(
                          pi >= 0 ? '继续阅读 ${_posPage + 1}页' : '开始阅读',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: n == 0 ? null : () => _open(0),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 38),
                          padding: EdgeInsets.zero,
                        ),
                        child: const Text('从头看',
                            maxLines: 1, overflow: TextOverflow.ellipsis),
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

  /// 点作者 / 点标签，去搜同一个作者、同一个标签。
  void _filter({String author = '', String tag = ''}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MangaFilterPage(author: author, tag: tag),
      ),
    );
  }

  Widget _chip(String text, {required bool author}) {
    final cs = Theme.of(context).colorScheme;
    final fg = author ? cs.onSurfaceVariant : cs.primary;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => _filter(author: author ? text : '', tag: author ? '' : text),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: author
              ? cs.surfaceContainerHighest.withValues(alpha: .8)
              : cs.primary.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(author ? Icons.person_outline : Icons.tag, size: 11, color: fg),
            const SizedBox(width: 3),
            Text(
              text,
              style: TextStyle(fontSize: 11, height: 1.2, color: fg),
            ),
          ],
        ),
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

  Widget _cover(MangaDetail d) {
    final cs = Theme.of(context).colorScheme;
    final done = d.status.contains('连载') ? '连载中' : (d.status.isEmpty ? '' : d.status);

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        children: [
          SizedBox(
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
          if (done.isNotEmpty)
            Positioned(
              left: 0,
              bottom: 0,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                color: cs.primary,
                child: Text(
                  done,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    height: 1.2,
                    color: cs.onPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _descBlock(MangaDetail d) {
    final cs = Theme.of(context).colorScheme;
    final desc = d.desc.trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => _descOpen = !_descOpen),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: .5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            desc,
            maxLines: _descOpen ? null : 3,
            overflow: _descOpen ? null : TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              height: 1.55,
              color: cs.onSurface.withValues(alpha: .85),
            ),
          ),
        ),
      ),
    );
  }

  Widget _chapterHeader(MangaDetail d) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 6),
      child: Row(
        children: [
          Text('连载体',
              style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(width: 4),
          Text('（${d.chapters.length} 话）',
              style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
          const Spacer(),
          TextButton.icon(
            onPressed: () => setState(() => _asc = !_asc),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            icon: Icon(_asc ? Icons.arrow_downward : Icons.arrow_upward,
                size: 15),
            label: Text(_asc ? '正序' : '倒序', style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _cell(MangaDetail d, MangaChapter c) {
    final cs = Theme.of(context).colorScheme;
    // 这里用 d.chapters（升序）算下标，别用显示顺序——_asc 只翻看的方向。
    final i = d.chapters.indexOf(c);
    final here = c.dir == _posCh;
    final read = !here && _posIndex >= 0 && i < _posIndex;
    return Material(
      color: here
          ? cs.primaryContainer
          : cs.surfaceContainerHighest
              .withValues(alpha: read ? .28 : .6),
      borderRadius: BorderRadius.circular(6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(i),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              c.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: here ? FontWeight.w600 : FontWeight.w400,
                color: here
                    ? cs.onPrimaryContainer
                    : (read ? cs.outline : cs.onSurface),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
