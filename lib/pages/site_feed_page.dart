import 'package:flutter/material.dart';

import '../api.dart';
import '../l10n/error_text.dart';
import '../l10n/l10n.dart';
import '../widgets/page_width.dart';
import '../widgets/empty_view.dart';
import '../widgets/thread_tile.dart';

/// 别的站上的帖子列表。
///
/// 只读：拉的是那座站的 `/feed`，不切站、不带本地 token。
/// 想回复就去那座站——切站是「站点管理」的事，不在浏览路径上做。
class SiteFeedPage extends StatefulWidget {
  final String name;
  final List<String> urls;

  const SiteFeedPage({super.key, required this.name, required this.urls});

  @override
  State<SiteFeedPage> createState() => _SiteFeedPageState();
}

class _SiteFeedPageState extends State<SiteFeedPage> {
  List<Map<String, dynamic>>? _items;
  ApiException? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await Api.getAt(widget.urls, '/feed');
      final raw = (d is Map ? d['items'] : null) as List?;
      if (!mounted) return;
      setState(() {
        _items = raw?.whereType<Map<String, dynamic>>().toList() ?? [];
        _err = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _items = [];
        _err = e;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Text(widget.name.isEmpty ? Lc.current.sites : widget.name),
      ),
      body: PageWidth(
        child: RefreshIndicator(
          onRefresh: _load,
          child: items == null
              ? const Center(child: CircularProgressIndicator())
              : items.isEmpty
              ? EmptyView(
                  icon: _err == null
                      ? Icons.forum_outlined
                      : Icons.cloud_off_rounded,
                  title: _err == null
                      ? Lc.current.siteNoPosts
                      : errorText(context, _err!),
                  error: _err != null,
                ).scrollable()
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox.shrink(),
                  itemBuilder: (_, i) => ThreadTile(
                    item: items[i],
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SiteThreadPage(
                          name: widget.name,
                          urls: widget.urls,
                          tid: (items[i]['id'] as num?)?.toInt() ?? 0,
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

/// 别的站上的一条帖子：正文 + 回复，只读。
class SiteThreadPage extends StatefulWidget {
  final String name;
  final List<String> urls;
  final int tid;

  const SiteThreadPage({
    super.key,
    required this.name,
    required this.urls,
    required this.tid,
  });

  @override
  State<SiteThreadPage> createState() => _SiteThreadPageState();
}

class _SiteThreadPageState extends State<SiteThreadPage> {
  Map<String, dynamic>? _thread;
  List<Map<String, dynamic>> _replies = const [];
  ApiException? _err;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await Api.getAt(widget.urls, '/t/${widget.tid}');
      final m = d is Map ? d : const {};
      if (!mounted) return;
      setState(() {
        _thread = (m['thread'] as Map?)?.cast<String, dynamic>();
        final raw = m['replies'] as List?;
        _replies = raw?.whereType<Map<String, dynamic>>().toList() ?? [];
        _err = null;
        _loaded = true;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _err = e;
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = _thread;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Text(
          (t?['title'] as String?)?.trim().isNotEmpty == true
              ? '${t!['title']}'
              : Lc.current.posts,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : _err != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  errorText(context, _err!),
                  style: TextStyle(color: cs.error),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Text(
                  '${t?['title'] ?? ''}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  '${t?['author'] ?? ''} · ${_time(t?['created_at'])}',
                  style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 14),
                SelectableText(
                  '${t?['body'] ?? ''}',
                  style: const TextStyle(fontSize: 15, height: 1.7),
                ),
                const SizedBox(height: 20),
                Divider(color: cs.outlineVariant),
                for (final r in _replies) ...[
                  const SizedBox(height: 14),
                  Text(
                    '${r['author'] ?? ''} · ${_time(r['created_at'])}',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    '${r['body'] ?? ''}',
                    style: const TextStyle(fontSize: 14.5, height: 1.65),
                  ),
                ],
                const SizedBox(height: 24),
                Text(
                  Lc.current.siteReadOnly,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: cs.outline),
                ),
              ],
            ),
    );
  }

  /// created_at 是秒级时间戳；缺了就空着，别编。
  String _time(Object? v) {
    if (v is! num || v <= 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(v.toInt() * 1000);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }
}
