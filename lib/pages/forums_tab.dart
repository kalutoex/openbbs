import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../store.dart';
import 'forum_page.dart';
import 'login_page.dart';

/// 板块页：一页滚到底。
///
/// 原来的两栏卡片网格太挤，改成单列行式列表——搜索常驻顶部，
/// 登录了就先把「我关注的」摆出来，下面接着全部的團。
class ForumsTab extends StatefulWidget {
  final VoidCallback onMenu;

  const ForumsTab({super.key, required this.onMenu});

  @override
  State<ForumsTab> createState() => _ForumsTabState();
}

class _ForumsTabState extends State<ForumsTab> {
  final _q = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;

  List<Map<String, dynamic>>? _all;
  List<Map<String, dynamic>>? _mine;
  String? _err;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadAll();
    _loadMine();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    try {
      final d = await Api.get('/forums', query: {'q': _query});
      if (!mounted) return;
      setState(() {
        _all = (d['items'] as List).cast<Map<String, dynamic>>();
        _err = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _err = e.message);
    }
  }

  Future<void> _loadMine() async {
    if (!AppState.instance.loggedIn) {
      if (mounted) setState(() => _mine = const []);
      return;
    }
    try {
      final d = await Api.get('/forums/mine');
      if (!mounted) return;
      setState(() => _mine = (d['items'] as List).cast<Map<String, dynamic>>());
    } on ApiException catch (_) {
      // 关注的團拉不动不算错，页面还有「全部」可用
      if (mounted) setState(() => _mine = const []);
    }
  }

  Future<void> _refresh() async {
    await Future.wait([_loadAll(), _loadMine()]);
  }

  void _onQueryChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() => _query = v.trim());
      _loadAll();
    });
    setState(() {});
  }

  void _open(Map<String, dynamic> f) {
    final name = (f['name'] ?? '') as String;
    final title = (f['title'] ?? name) as String;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ForumPage(name: name, title: title),
      ),
    );
  }

  Future<void> _goLogin() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const LoginPage()));
    if (mounted) {
      await Future.wait([_loadMine(), _loadAll()]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: widget.onMenu,
          icon: const Icon(Icons.menu),
          tooltip: '菜单',
        ),
        titleSpacing: 4,
        title: const Text(
          '板块',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 19),
        ),
        actions: [
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            _searchBox(cs),
            if (_err != null)
              _errorBox(cs)
            else if (_all == null)
              _loading()
            else if (_query.isNotEmpty)
              ..._searchResults(cs)
            else
              ..._browse(cs),
          ],
        ),
      ),
    );
  }

  Widget _searchBox(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
      child: TextField(
        controller: _q,
        onChanged: _onQueryChanged,
        textInputAction: TextInputAction.search,
        onSubmitted: (v) {
          _debounce?.cancel();
          setState(() => _query = v.trim());
          _loadAll();
        },
        decoration: InputDecoration(
          isDense: true,
          hintText: '搜團',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _q.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: '清空',
                  onPressed: () {
                    _q.clear();
                    _debounce?.cancel();
                    setState(() => _query = '');
                    _loadAll();
                  },
                ),
          filled: true,
          fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.42),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide(color: cs.primary.withValues(alpha: 0.6)),
          ),
        ),
      ),
    );
  }

  Widget _errorBox(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 60, 24, 0),
      child: Column(
        children: [
          Icon(Icons.cloud_off, size: 34, color: cs.outline),
          const SizedBox(height: 10),
          Text(
            _err!,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          OutlinedButton(onPressed: _refresh, child: const Text('再试一次')),
        ],
      ),
    );
  }

  /// 首屏占位。用静态灰块，不带动画——
  /// 带动画的骨架会让 pumpAndSettle 永远等不到静止，测试跟着一起卡死。
  Widget _loading() {
    final cs = Theme.of(context).colorScheme;
    Widget bar(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(4),
      ),
    );
    return Column(
      children: [
        const SizedBox(height: 12),
        for (var i = 0; i < 6; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      bar(90.0 + (i % 3) * 26, 13),
                      const SizedBox(height: 7),
                      bar(150.0 + (i % 2) * 40, 11),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  List<Widget> _searchResults(ColorScheme cs) {
    final items = _all ?? const <Map<String, dynamic>>[];
    if (items.isEmpty) {
      return [
        const SizedBox(height: 70),
        Center(
          child: Column(
            children: [
              Icon(Icons.search_off, size: 34, color: cs.outline),
              const SizedBox(height: 10),
              Text(
                '没搜到「$_query」',
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ];
    }
    return [
      _header('搜到 ${items.length} 个', cs),
      for (final f in items) _row(f, cs),
    ];
  }

  List<Widget> _browse(ColorScheme cs) {
    final all = _all ?? const <Map<String, dynamic>>[];
    final mine = _mine ?? const <Map<String, dynamic>>[];
    return [
      if (!AppState.instance.loggedIn)
        _loginHint(cs)
      else if (mine.isEmpty)
        _emptyMine(cs)
      else ...[
        _header('我关注的 ${mine.length}', cs),
        for (final f in mine) _row(f, cs),
        const SizedBox(height: 8),
      ],
      _header('全部 ${all.length}', cs),
      if (all.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 30, 24, 0),
          child: Center(
            child: Text(
              '还没有建板块',
              style: TextStyle(fontSize: 13, color: cs.outline),
            ),
          ),
        ),
      for (final f in all) _row(f, cs),
    ];
  }

  Widget _header(String text, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _loginHint(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _goLogin,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: cs.primaryContainer.withValues(alpha: 0.5),
          ),
          child: Row(
            children: [
              Icon(Icons.bookmark_border, size: 18, color: cs.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '登录后能看到关注过的團',
                  style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                ),
              ),
              Text(
                '去登录',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: cs.primary,
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: cs.primary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyMine(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
        ),
        child: Row(
          children: [
            Icon(Icons.bookmark_border, size: 18, color: cs.outline),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '还没关注團，进一个點关注',
                style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(Map<String, dynamic> f, ColorScheme cs) {
    final name = (f['name'] ?? '') as String;
    final title = (f['title'] ?? name) as String;
    final intro = (f['intro'] ?? '') as String;
    final threads = f['thread_count'] ?? 0;
    final followers = f['follow_count'] ?? 0;
    final hue = (name.hashCode % 360).abs();

    return InkWell(
      onTap: () => _open(f),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 9, 10, 9),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: HSLColor.fromAHSL(
                  1,
                  hue.toDouble(),
                  0.32,
                  0.88,
                ).toColor(),
              ),
              child: Text(
                title.isEmpty ? '?' : title.substring(0, 1),
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: HSLColor.fromAHSL(
                    1,
                    hue.toDouble(),
                    0.55,
                    0.32,
                  ).toColor(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    intro.isEmpty ? '还没有简介' : intro,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$threads 線 · $followers 关注',
                    style: TextStyle(fontSize: 11, color: cs.outline),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: cs.outlineVariant),
          ],
        ),
      ),
    );
  }
}
