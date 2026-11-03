import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api.dart';
import '../widgets/thread_tile.dart';
import 'thread_page.dart';
import 'user_page.dart';

import '../l10n/error_text.dart';
import '../l10n/l10n.dart';
/// 全站搜索：按标题和正文匹配。
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _ctl = TextEditingController();
  final FocusNode _focus = FocusNode();
  final ScrollController _scroll = ScrollController();
  final List<Map<String, dynamic>> _items = [];
  final List<String> _hist = [];
  static const _kHist = 'search_hist';

  String _q = '';
  int _page = 1;
  int _seq = 0;
  int _total = 0;
  bool _busy = false;
  bool _hasMore = true;
  bool _searched = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - _ahead) {
        _load();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
    _loadHist();
  }

  Future<void> _loadHist() async {
    final p = await SharedPreferences.getInstance();
    final v = p.getStringList(_kHist) ?? [];
    if (!mounted) return;
    setState(() {
      _hist
        ..clear()
        ..addAll(v);
    });
  }

  Future<void> _pushHist(String q) async {
    _hist.remove(q);
    _hist.insert(0, q);
    if (_hist.length > 12) _hist.removeRange(12, _hist.length);
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kHist, _hist);
    if (mounted) setState(() {});
  }

  Future<void> _clearHist() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kHist);
    if (!mounted) return;
    setState(_hist.clear);
  }


  /// 离底还有一屏就开始拉下一页，滑到底时内容已经在手上了。
  double get _ahead {
    final vp = _scroll.hasClients ? _scroll.position.viewportDimension : 0.0;
    return vp > 0 ? vp : 400;
  }

  @override
  void dispose() {
    _ctl.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// 搜的是人还是内容：给 handle / 用户名 / UID 都认，找不到返回 null。
  Future<String?> _resolveUser(String q) async {
    final key = q.replaceFirst(RegExp(r'^@'), '').trim();
    if (key.isEmpty) return null;
    try {
      await Api.get('/u/${Uri.encodeComponent(key)}');
      return key;
    } on ApiException {
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _submit(String raw) async {
    final q = raw.trim();
    if (q.isEmpty) return;
    _pushHist(q);
    // 先按身份标识 / UID 试一下，能认出来就直接进主页。
    final who = await _resolveUser(q);
    if (!mounted) return;
    if (who != null) {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => UserPage(name: who)));
      return;
    }
    if (q == _q && _items.isNotEmpty) return;
    // 换词就换号并放行：上一个词的分页请求还在飞的话，回来不许往新结果里塞。
    _seq++;
    _busy = false;
    setState(() {
      _q = q;
      _items.clear();
      _page = 1;
      _total = 0;
      _err = null;
      _hasMore = true;
      _searched = true;
    });
    _focus.unfocus();
    await _load();
  }

  Future<void> _load() async {
    if (_busy || !_hasMore || _q.isEmpty) return;
    final seq = _seq;
    _busy = true;
    try {
      final d = await Api.get('/search', query: {'q': _q, 'page': '$_page'});
      final items = (d['items'] as List).cast<Map<String, dynamic>>();
      if (!mounted || seq != _seq) return;
      setState(() {
        _items.addAll(items);
        _total = (d['total'] ?? 0) as int;
        _page++;
        _hasMore = items.length >= 20 && _items.length < _total;
        _err = null;
      });
    } on ApiException catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() => _err = errorText(context, e));
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
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _ctl,
          focusNode: _focus,
          textInputAction: TextInputAction.search,
          onSubmitted: _submit,
          decoration: InputDecoration(
            hintText: Lc.current.searchTitleOrBody,
            border: InputBorder.none,
          ),
        ),
        actions: [
          IconButton(
            onPressed: () => _submit(_ctl.text),
            icon: const Icon(Icons.search),
            tooltip: Lc.current.search,
          ),
        ],
      ),
      body: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (!_searched) {
      if (_hist.isEmpty) {
        return Center(
          child: Text(
            Lc.current.searchPrompt,
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        );
      }
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        children: [
          Row(
            children: [
              Text(Lc.current.recentSearches, style: TextStyle(fontSize: 12, color: cs.outline)),
              const Spacer(),
              TextButton(
                onPressed: _clearHist,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(Lc.current.clearAll, style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final h in _hist)
                ActionChip(
                  label: Text(h, style: const TextStyle(fontSize: 13)),
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    _ctl.text = h;
                    _submit(h);
                  },
                ),
            ],
          ),
        ],
      );
    }

    if (_err != null && _items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _err!,
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.error),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: () => _submit(_q),
              child: Text(Lc.current.retry),
            ),
          ],
        ),
      );
    }

    if (_items.isEmpty) {
      if (_busy) return const Center(child: CircularProgressIndicator());
      return Center(
        child: Text(Lc.current.noSearchResult('${_q}'), style: TextStyle(color: cs.onSurfaceVariant)),
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
                _busy ? Lc.current.loading : (_hasMore ? Lc.current.totalCount('${_total}') : Lc.current.endTotalCount('${_total}')),
                style: TextStyle(color: cs.outline, fontSize: 12),
              ),
            ),
          );
        }
        final it = _items[i];
        return ThreadTile(item: it, onTap: () => _open(it), onDeleted: () {});
      },
    );
  }
}
