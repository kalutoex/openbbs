import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../user_hue.dart';
import '../api.dart';
import '../widgets/empty_view.dart';
import '../widgets/page_width.dart';
import '../widgets/avatar.dart';
import '../widgets/thread_tile.dart';
import 'thread_page.dart';
import 'user_page.dart';

import '../l10n/error_text.dart';
import '../l10n/l10n.dart';

/// 全站搜索：帖子 / 回复 / 用户。
///
/// 三段共用一个输入框，切换只看上面那排 chip。
/// 帖子会翻页，回复和用户各只取前 20 条 —— 翻页搜人没意义。
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
  final List<Map<String, dynamic>> _replies = [];
  final List<Map<String, dynamic>> _users = [];
  final List<String> _hist = [];
  static const _kHist = 'search_history_v1';

  String _q = '';
  String _kind = 'thread';
  int _page = 1;
  int _seq = 0;
  int _total = 0;
  bool _busy = false;
  bool _hasMore = true;
  bool _searched = false;
  String? _err;

  static const _kinds = ['thread', 'reply', 'user'];

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
    if (_hist.length > 10) _hist.removeRange(10, _hist.length);
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kHist, _hist);
    if (mounted) setState(() {});
  }

  /// 长按单条删掉，不用为了清一个词把历史全清了。
  Future<void> _delHist(String q) async {
    _hist.remove(q);
    final p = await SharedPreferences.getInstance();
    if (_hist.isEmpty) {
      await p.remove(_kHist);
    } else {
      await p.setStringList(_kHist, _hist);
    }
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
    // 只在搜帖子时试一下"这个词是不是某个人"；搜回复/用户时按列表展示，别直接跳走。
    if (_kind == 'thread') {
      final who = await _resolveUser(q);
      if (!mounted) return;
      if (who != null) {
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => UserPage(name: who)));
        return;
      }
    }
    if (q == _q &&
        (_items.isNotEmpty || _replies.isNotEmpty || _users.isNotEmpty)) {
      return;
    }
    // 换词就换号并放行：上一个词的分页请求还在飞的话，回来不许往新结果里塞。
    _seq++;
    _busy = false;
    setState(() {
      _q = q;
      _items.clear();
      _replies.clear();
      _users.clear();
      _page = 1;
      _total = 0;
      _err = null;
      _hasMore = true;
      _searched = true;
    });
    _focus.unfocus();
    await _load();
  }

  void _switchKind(String k) {
    if (k == _kind) return;
    setState(() {
      _kind = k;
      _items.clear();
      _replies.clear();
      _users.clear();
      _page = 1;
      _total = 0;
      _hasMore = true;
      _seq++;
    });
    if (_q.isNotEmpty) _load();
  }

  Future<void> _load() async {
    if (_busy || _q.isEmpty) return;
    if (_kind == 'thread' && !_hasMore) return;
    if (_kind != 'thread' && _searched && _replies.isNotEmpty) return;
    if (_kind != 'thread' && _searched && _users.isNotEmpty) return;
    final seq = _seq;
    final kind = _kind;
    _busy = true;
    try {
      final d = await Api.get(
        '/search',
        query: {'q': _q, 'page': '$_page', 'kind': kind},
      );
      if (!mounted || seq != _seq) return;
      final items = (d['items'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      final reps = (d['replies'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      final us = (d['users'] as List? ?? const []).cast<Map<String, dynamic>>();
      setState(() {
        if (kind == 'thread') {
          _items.addAll(items);
          _total = (d['total'] ?? 0) as int;
          _page++;
          _hasMore = items.length >= 20 && _items.length < _total;
        } else if (kind == 'reply') {
          _replies
            ..clear()
            ..addAll(reps);
        } else {
          _users
            ..clear()
            ..addAll(us);
        }
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

  void _openReply(Map<String, dynamic> r) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ThreadPage(
          threadId: r['thread_id'] as int,
          title: (r['thread_title'] ?? '') as String,
        ),
      ),
    );
  }

  void _openUser(Map<String, dynamic> u) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UserPage(name: (u['name'] ?? '') as String),
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
      body: PageWidth(
        child: Column(
          children: [
            if (_searched) _kindBar(context),
            Expanded(child: _body(context)),
          ],
        ),
      ),
    );
  }

  Widget _kindBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final labels = {
      'thread': Lc.current.searchThreads,
      'reply': Lc.current.searchReplies,
      'user': Lc.current.searchUsers,
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant, width: 0.5),
        ),
      ),
      child: Wrap(
        spacing: 8,
        children: [
          for (final k in _kinds)
            ChoiceChip(
              label: Text(labels[k]!, style: const TextStyle(fontSize: 13)),
              selected: _kind == k,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => _switchKind(k),
            ),
        ],
      ),
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
              Text(
                Lc.current.recentSearches,
                style: TextStyle(fontSize: 12, color: cs.outline),
              ),
              const Spacer(),
              TextButton(
                onPressed: _clearHist,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  Lc.current.clearAll,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final h in _hist)
                // ActionChip 这版没有 onLongPress，外面裹一层接长按删单条。
                GestureDetector(
                  onLongPress: () => _delHist(h),
                  child: ActionChip(
                    label: Text(h, style: const TextStyle(fontSize: 13)),
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      _ctl.text = h;
                      _submit(h);
                    },
                  ),
                ),
            ],
          ),
        ],
      );
    }

    if (_kind == 'reply') return _replyList(context);
    if (_kind == 'user') return _userList(context);

    if (_err != null && _items.isEmpty) {
      return EmptyView(
        icon: Icons.cloud_off_rounded,
        title: Lc.current.loadFailed,
        hint: _err,
        error: true,
        action: FilledButton.tonal(
          onPressed: () => _submit(_q),
          child: Text(Lc.current.retry),
        ),
      );
    }

    if (_items.isEmpty) {
      if (_busy) return const Center(child: CircularProgressIndicator());
      return EmptyView(
        icon: Icons.search_off_rounded,
        title: Lc.current.noSearchResult(_q),
      );
    }

    return ListView.separated(
      controller: _scroll,
      itemCount: _items.length + 1,
      separatorBuilder: (_, i) => const SizedBox.shrink(),
      itemBuilder: (context, i) {
        if (i == _items.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: Text(
                _busy
                    ? Lc.current.loading
                    : (_hasMore
                          ? Lc.current.totalCount('$_total')
                          : Lc.current.endTotalCount('$_total')),
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

  Widget _replyList(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_busy && _replies.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_replies.isEmpty) {
      return Center(
        child: Text(
          Lc.current.noSearchResult(_q),
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
      );
    }
    return ListView.separated(
      itemCount: _replies.length,
      separatorBuilder: (_, i) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final r = _replies[i];
        final who = (r['author'] ?? '') as String;
        final handle = (r['handle'] ?? '') as String;
        return InkWell(
          onTap: () => _openReply(r),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (r['thread_title'] ?? '') as String,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  (r['excerpt'] ?? '') as String,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 4),
                Text(
                  handle.isEmpty ? who : '$who  @$handle',
                  style: TextStyle(fontSize: 11, color: cs.outline),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _userList(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_busy && _users.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_users.isEmpty) {
      return Center(
        child: Text(
          Lc.current.noSearchResult(_q),
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
      );
    }
    return ListView.separated(
      itemCount: _users.length,
      separatorBuilder: (_, i) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final u = _users[i];
        final name = (u['nickname'] ?? u['name'] ?? '') as String;
        final handle = (u['handle'] ?? '') as String;
        final sign = (u['signature'] ?? '') as String;
        return ListTile(
          leading: CircleAvatarImg(
            url: (u['avatar'] ?? '') as String,
            name: name,
            radius: 20,
            hue: hueOfUser(u),
          ),
          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            sign.isEmpty
                ? (handle.isEmpty ? '' : '@$handle')
                : '@$handle · $sign',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => _openUser(u),
        );
      },
    );
  }
}
