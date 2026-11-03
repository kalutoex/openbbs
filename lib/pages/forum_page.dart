import 'package:flutter/material.dart';

import '../api.dart';
import '../store.dart';
import '../widgets/thread_tile.dart';
import 'thread_page.dart';

import '../l10n/error_text.dart';
/// 单个吧。
class ForumPage extends StatefulWidget {
  final String name;
  final String title;

  const ForumPage({super.key, required this.name, required this.title});

  @override
  State<ForumPage> createState() => _ForumPageState();
}

class _ForumPageState extends State<ForumPage> {
  final List<Map<String, dynamic>> _items = [];
  final ScrollController _scroll = ScrollController();
  Map<String, dynamic>? _forum;
  String _sort = 'last';
  int _page = 1;
  bool _busy = false;
  bool _hasMore = true;
  bool _first = true;
  String? _err;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 320) {
        _load();
      }
    });
    _reload();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _first = true;
      _err = null;
    });
    _items.clear();
    _page = 1;
    _hasMore = true;
    await _load();
  }

  Future<void> _load() async {
    if (_busy || !_hasMore) return;
    _busy = true;
    try {
      final d = await Api.get(
        '/f/${Uri.encodeComponent(widget.name)}',
        query: {'page': '$_page', 'sort': _sort},
      );
      final items = (d['items'] as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _forum = d['forum'] as Map<String, dynamic>;
        _items.addAll(items);
        _hasMore = items.length >= 20;
        _page++;
        _first = false;
        _err = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _first = false;
        _err = errorText(context, e);
      });
    } finally {
      _busy = false;
    }
  }

  Future<void> _toggleFollow() async {
    if (!AppState.instance.loggedIn) {
      _toast('先登录');
      return;
    }
    try {
      final d = await Api.post(
        '/f/${Uri.encodeComponent(widget.name)}/follow',
        {},
      );
      setState(() {
        _forum?['followed'] = d['followed'];
        final n = (_forum?['follow_count'] ?? 0) as int;
        _forum?['follow_count'] = d['followed'] == true
            ? n + 1
            : (n > 0 ? n - 1 : 0);
      });
    } on ApiException catch (e) {
      _toast(e);
    }
  }

  void _toast(Object s) {
    if (!mounted) return;
    final t = s is String ? s : errorText(context, s);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final f = _forum;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: SizedBox(
            height: 48,
            child: Row(
              children: [
                _sortChip('最新回复', 'last', cs),
                _sortChip('最新发布', 'new', cs),
                _sortChip('热门', 'hot', cs),
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (f != null) _header(f, cs),
            if (_first)
              const Padding(
                padding: EdgeInsets.only(top: 60),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_err != null)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text(_err!, style: TextStyle(color: cs.error)),
                ),
              )
            else if (_items.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 60),
                child: Center(child: Text('这个團还没有線')),
              )
            else
              for (final it in _items) ...[
                ThreadTile(
                  item: it,
                  onDeleted: _reload,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ThreadPage(
                        threadId: it['id'] as int,
                        title: (it['title'] ?? '') as String,
                      ),
                    ),
                  ),
                ),
                Divider(
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                  color: cs.outlineVariant.withValues(alpha: 0.4),
                ),
              ],
            if (!_first && _items.isNotEmpty && !_hasMore)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text('到底了', style: TextStyle(color: cs.outline)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _sortChip(String label, String value, ColorScheme cs) {
    final on = _sort == value;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: TextButton(
        onPressed: () {
          if (_sort == value) return;
          setState(() => _sort = value);
          _reload();
        },
        style: TextButton.styleFrom(
          foregroundColor: on ? cs.primary : cs.onSurfaceVariant,
          textStyle: TextStyle(
            fontWeight: on ? FontWeight.w700 : FontWeight.w400,
          ),
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
        child: Text(label),
      ),
    );
  }

  Widget _header(Map<String, dynamic> f, ColorScheme cs) {
    final followed = f['followed'] == true;
    final title = (f['title'] ?? '') as String;
    final intro = (f['intro'] ?? '') as String;
    final btnStyle = FilledButton.styleFrom(
      minimumSize: const Size(0, 36),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    );
    final outStyle = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 36),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 15),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  title.isEmpty ? '?' : title.substring(0, 1),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: cs.onPrimaryContainer,
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${f['thread_count'] ?? 0} 帖 · ${f['follow_count'] ?? 0} 关注',
                      style: TextStyle(fontSize: 11, color: cs.outline),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              followed
                  ? OutlinedButton(
                      onPressed: _toggleFollow,
                      style: outStyle,
                      child: const Text('已关注'),
                    )
                  : FilledButton(
                      onPressed: _toggleFollow,
                      style: btnStyle,
                      child: const Text('关注'),
                    ),
            ],
          ),
          if (intro.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              intro,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
