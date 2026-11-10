import 'package:flutter/material.dart';

import '../api.dart';
import '../paged.dart';
import '../widgets/empty_view.dart';
import '../widgets/page_width.dart';
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
  final ScrollController _scroll = ScrollController();

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
    setState(() {});
    await _pager.reset();
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
    if (_pager.first) {
      return const Center(child: CircularProgressIndicator());
    }

    final err = _pager.error;
    if (err != null && _pager.isEmpty) {
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

    if (_pager.isEmpty) {
      return EmptyView(
        icon: Icons.inbox_outlined,
        title: widget.emptyText,
      ).scrollable();
    }

    return ListView.separated(
      controller: _scroll,
      itemCount: _pager.items.length + 1,
      separatorBuilder: (_, i) => const SizedBox.shrink(),
      itemBuilder: (context, i) {
        if (i == _pager.items.length) {
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
        final it = _pager.items[i];
        return ThreadTile(item: it, onTap: () => _open(it), onDeleted: _reload);
      },
    );
  }
}
