import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../manga.dart';
import '../widgets/retry_image.dart';
import '../widgets/empty_view.dart';
import '../widgets/page_width.dart';
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

  String get _posKey => 'manga_pos_${widget.book.dir}';

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
        final raw = sp.getString(_posKey);
        if (raw != null && raw.contains('|')) {
          final cut = raw.lastIndexOf('|');
          ch = raw.substring(0, cut);
          page = int.tryParse(raw.substring(cut + 1)) ?? 0;
        }
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _d = d;
        _err = null;
        _posCh = ch;
        _posPage = page;
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
        builder: (_) => MangaReaderPage(detail: d, index: i),
      ),
    ).then((_) => _load());
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

    final tags = [
      if (d.types.isNotEmpty) d.types,
    ].where((s) => s.isNotEmpty).join(' ');

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
                if (d.authors.isNotEmpty)
                  _iconLine(Icons.person_outline, d.authors),
                if (tags.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _iconLine(Icons.tag, tags, color: cs.primary),
                ],
                const SizedBox(height: 6),
                _iconLine(Icons.schedule, '$n 话已下载'),
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
    final here = c.dir == _posCh;
    return Material(
      color: here ? cs.primaryContainer : cs.surfaceContainerHighest.withValues(alpha: .6),
      borderRadius: BorderRadius.circular(6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(d.chapters.indexOf(c)),
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
                color: here ? cs.onPrimaryContainer : cs.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
