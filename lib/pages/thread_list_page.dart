import 'package:flutter/material.dart';

import '../api.dart';
import '../widgets/thread_tile.dart';
import 'thread_page.dart';

import '../l10n/error_text.dart';
import '../l10n/l10n.dart';
/// 一条只有帖子列表的页：收藏、浏览历史共用。
class ThreadListPage extends StatefulWidget {
  final String title;
  final String path;
  final String emptyText;

  const ThreadListPage({
    super.key,
    required this.title,
    required this.path,
    required this.emptyText,
  });

  @override
  State<ThreadListPage> createState() => _ThreadListPageState();
}

class _ThreadListPageState extends State<ThreadListPage> {
  final List<Map<String, dynamic>> _items = [];
  final ScrollController _scroll = ScrollController();

  int _page = 1;
  bool _busy = false;
  int _seq = 0;
  bool _hasMore = true;
  bool _first = true;
  String? _err;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - _ahead) {
        _load();
      }
    });
    _load();
  }


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
    // 换号：之前滑出来的那几页还在飞的话，回来也不作数了。
    final seq = ++_seq;
    setState(() {
      _items.clear();
      _page = 1;
      _hasMore = true;
      _first = true;
      _err = null;
    });
    _busy = true;
    try {
      final d = await Api.get(widget.path, query: {'page': '1'});
      final items = (d['items'] as List).cast<Map<String, dynamic>>();
      if (!mounted || seq != _seq) return;
      setState(() {
        _items.addAll(items);
        _page = 2;
        _hasMore = items.length >= 20;
        _first = false;
        _err = null;
      });
    } on ApiException catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _first = false;
        _err = errorText(context, e);
      });
    } finally {
      if (seq == _seq) _busy = false;
    }
  }

  Future<void> _load() async {
    if (_busy || !_hasMore) return;
    final seq = _seq;
    _busy = true;
    try {
      final d = await Api.get(widget.path, query: {'page': '$_page'});
      final items = (d['items'] as List).cast<Map<String, dynamic>>();
      if (!mounted || seq != _seq) return;
      setState(() {
        _items.addAll(items);
        _page++;
        _hasMore = items.length >= 20;
        _first = false;
        _err = null;
      });
    } on ApiException catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _first = false;
        _err = errorText(context, e);
      });
    } finally {
      if (seq == _seq) _busy = false;
    }
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
      body: RefreshIndicator(onRefresh: _reload, child: _body(context, cs)),
    );
  }

  Widget _body(BuildContext context, ColorScheme cs) {
    if (_first) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_err != null && _items.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _err!,
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.error),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: FilledButton.tonal(
              onPressed: _reload,
              child: Text(Lc.current.retry),
            ),
          ),
        ],
      );
    }

    if (_items.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 140),
          Center(
            child: Text(
              widget.emptyText,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      controller: _scroll,
      itemCount: _items.length + 1,
      separatorBuilder: (_, i) => const Divider(height: 1),
      itemBuilder: (context, i) {
        if (i == _items.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: Text(
                _busy ? Lc.current.loading : (_hasMore ? Lc.current.moreToLoad : Lc.current.endOfList),
                style: TextStyle(color: cs.outline, fontSize: 12),
              ),
            ),
          );
        }
        final it = _items[i];
        return ThreadTile(item: it, onTap: () => _open(it), onDeleted: _reload);
      },
    );
  }
}
