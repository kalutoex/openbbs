import 'dart:async';

import 'package:flutter/material.dart';

import '../manga_source.dart';
import '../widgets/empty_view.dart';
import '../widgets/page_width.dart';
import '../widgets/retry_image.dart';
import 'source_book_page.dart';

/// 搜书源：一次问所有开着的源，回来多少算多少。
///
/// 二十几个源串着问要一分多钟，所以后端一起发、谁先回来算谁的，
/// 慢的到点就丢——宁可少几个结果，也不让人盯着转圈。
class SourceSearchPage extends StatefulWidget {
  const SourceSearchPage({super.key});

  @override
  State<SourceSearchPage> createState() => _SourceSearchPageState();
}

class _SourceSearchPageState extends State<SourceSearchPage> {
  final _ctl = TextEditingController();
  final _focus = FocusNode();
  SourceSearch? _res;
  bool _busy = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _ctl.text.trim();
    if (q.isEmpty || _busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final r = await SourceApi.search(q);
      if (!mounted) return;
      setState(() {
        _res = r;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _err = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _ctl,
          focusNode: _focus,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
          decoration: InputDecoration(
            hintText: '搜书名，比如 海贼王',
            border: InputBorder.none,
            suffixIcon: _ctl.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(_ctl.clear),
                  ),
          ),
          onChanged: (_) => setState(() {}),
        ),
        actions: [
          IconButton(
            onPressed: _busy ? null : _search,
            icon: const Icon(Icons.search),
            tooltip: '搜',
          ),
        ],
      ),
      body: _busy
          ? _searching(cs)
          : _err != null
              ? EmptyView(
                  icon: Icons.cloud_off,
                  title: '搜不了',
                  hint: _err,
                  error: true,
                  action: TextButton(
                      onPressed: _search, child: const Text('重试')),
                )
              : _res == null
                  ? _hint(cs)
                  : _result(_res!),
    );
  }

  Widget _hint(ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Text(
          '输入书名，会同时在所有开着的漫画源里找一遍。\n'
          '源站有的能搜到有的不能，搜不到就换一个源再试。',
          textAlign: TextAlign.center,
          style: TextStyle(color: cs.onSurfaceVariant, height: 1.6),
        ),
      ),
    );
  }

  Widget _searching(ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            height: 22,
            width: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(height: 14),
          Text(
            '正在问所有源…',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _result(SourceSearch r) {
    final cs = Theme.of(context).colorScheme;
    final hit = r.hit;
    final miss = r.miss;

    if (hit.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          EmptyView(
            icon: Icons.search_off,
            title: '一个源都没搜到',
            hint: '问了 ${r.groups.length} 个源，${(r.ms / 1000).toStringAsFixed(1)} 秒。'
                '换个名字，或者换个源再试。',
          ),
          if (miss.isNotEmpty) _missLine(miss, cs),
        ],
      );
    }

    return PageWidth(
      max: 1100,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 28),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
            child: Text(
              '${r.total} 本 · ${hit.length} 个源有结果 · '
              '${(r.ms / 1000).toStringAsFixed(1)} 秒',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ),
          for (final g in hit) _group(g),
          if (miss.isNotEmpty) _missLine(miss, cs),
        ],
      ),
    );
  }

  Widget _missLine(List<SourceGroup> miss, ColorScheme cs) {
    final dead = miss.where((g) => !g.ok).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Text(
        '另有 ${miss.length} 个源没有结果'
        '${dead > 0 ? '（其中 $dead 个连不上）' : ''}：'
        '${miss.take(8).map((g) => g.name).join('、')}'
        '${miss.length > 8 ? '…' : ''}',
        style: TextStyle(fontSize: 11.5, height: 1.5, color: cs.outline),
      ),
    );
  }

  Widget _group(SourceGroup g) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Row(
            children: [
              Icon(Icons.dns_outlined, size: 14, color: cs.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  g.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Text(
                '${g.books.length} 本 · ${g.ms}ms',
                style: TextStyle(fontSize: 11, color: cs.outline),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 186,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: g.books.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) => _card(g.books[i]),
          ),
        ),
      ],
    );
  }

  Widget _card(SourceBook b) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return SizedBox(
      width: 100,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => SourceBookPage(book: b)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: b.coverThumb.isEmpty
                    ? Container(
                        color: cs.surfaceContainerHighest,
                        child: Icon(Icons.menu_book, color: cs.outline),
                      )
                    : RetryImage(
                        url: b.coverThumb,
                        fit: BoxFit.cover,
                        memCacheWidth: 320,
                        probeSize: false,
                      ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              b.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            Text(
              b.author.isEmpty ? ' ' : b.author,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
