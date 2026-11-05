import 'package:flutter/material.dart';

import '../api.dart';
import '../l10n/error_text.dart';
import '../l10n/l10n.dart';
import '../sites.dart';
import '../store.dart';
import 'site_feed_page.dart';
import '../widgets/app_card.dart';
import '../widgets/empty_view.dart';
import '../widgets/page_width.dart';

/// 主页第二个 tab：站点目录。
///
/// 这里只管「去哪儿看」——点一座站进去看它的帖子。
/// 切站、增删、登录站在设置里的「站点管理」，别混在一块。
class SiteCatalogPage extends StatefulWidget {
  final VoidCallback? onMenu;

  const SiteCatalogPage({super.key, this.onMenu});

  @override
  State<SiteCatalogPage> createState() => _SiteCatalogPageState();
}

/// 目录里的一行。远端目录和本地表合起来就是一个列表。
class _CatalogItem {
  final String name;
  final String desc;
  final List<String> urls;
  final bool master;

  const _CatalogItem({
    required this.name,
    required this.desc,
    required this.urls,
    this.master = false,
  });
}

class _SiteCatalogPageState extends State<SiteCatalogPage> {
  List<_CatalogItem>? _items;
  ApiException? _err;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    AppState.instance.addListener(_onState);
    _load();
  }

  void _onState() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AppState.instance.removeListener(_onState);
    super.dispose();
  }

  /// 目录 = 本地表里的站 + 主站收录的站。
  ///
  /// 本地有的优先：名字是用户起的，入口也探过了。主站目录补充「还没加过」的站，
  /// 读到就算收录，不需要先加进表里。
  Future<void> _load() async {
    if (_busy) return;
    _busy = true;
    final st = AppState.instance;
    final local = st.sites.where((s) => s.valid).toList();
    final masterUrls = st.masterSite?.orderedUrls ?? const <String>[];
    var remote = const <Map<String, dynamic>>[];
    ApiException? err;
    try {
      if (masterUrls.isNotEmpty) {
        final d = await Api.getAt(masterUrls, '/sites');
        final raw = (d is Map ? d['sites'] : null) as List?;
        if (raw != null) {
          remote = raw.whereType<Map<String, dynamic>>().toList();
        }
      }
    } on ApiException catch (e) {
      err = e;
    }

    final out = <_CatalogItem>[];
    final seen = <String>{};
    for (final s in local) {
      out.add(
        _CatalogItem(
          name: s.display,
          desc: '',
          urls: s.orderedUrls,
          master: s.isHome,
        ),
      );
      for (final u in s.urls) {
        final h = hostOf(u);
        if (h.isNotEmpty) seen.add(h);
      }
    }
    for (final r in remote) {
      final host = hostOf('${r['url'] ?? ''}');
      if (host.isEmpty || seen.contains(host)) continue;
      seen.add(host);
      final urls = <String>[];
      final first = '${r['url'] ?? ''}'.trim();
      if (first.isNotEmpty) urls.add(first);
      for (final e in (r['endpoints'] as List?) ?? const []) {
        final u = (e is Map ? '${e['url'] ?? ''}' : '$e').trim();
        if (u.isNotEmpty && !urls.contains(u)) urls.add(u);
      }
      if (urls.isEmpty) continue;
      out.add(
        _CatalogItem(
          name: '${r['name'] ?? ''}'.trim(),
          desc: '${r['description'] ?? ''}'.trim(),
          urls: urls,
        ),
      );
    }

    // 屏蔽的站不出现——这就是「屏蔽」的全部意义。
    final blocked = <String>{};
    for (final s in st.sites) {
      if (!s.blocked) continue;
      for (final u in s.urls) {
        final h = hostOf(u);
        if (h.isNotEmpty) blocked.add(h);
      }
    }
    final visible = out
        .where((it) => !it.urls.any((u) => blocked.contains(hostOf(u))))
        .toList();

    if (!mounted) return;
    setState(() {
      _items = visible;
      _err = err;
      _busy = false;
    });
  }

  void _open(_CatalogItem it) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SiteFeedPage(name: it.name, urls: it.urls),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = _items;
    return Scaffold(
      appBar: AppBar(
        leading: widget.onMenu == null
            ? null
            : IconButton(
                onPressed: widget.onMenu,
                icon: const Icon(Icons.menu_rounded),
                tooltip: Lc.current.menu,
              ),
        titleSpacing: 0,
        title: Text(Lc.current.sites),
        actions: [
          IconButton(
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: Lc.current.refresh,
          ),
        ],
      ),
      body: PageWidth(
        child: RefreshIndicator(
          onRefresh: _load,
          child: items == null
              ? const Center(child: CircularProgressIndicator())
              : items.isEmpty
              ? _empty(cs)
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 32),
                  itemCount: items.length,
                  itemBuilder: (_, i) => AppCard(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: _row(items[i], cs),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _row(_CatalogItem it, ColorScheme cs) => ListTile(
    contentPadding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
    leading: CircleAvatar(
      backgroundColor: cs.secondaryContainer,
      child: Text(
        it.name.isEmpty ? '?' : it.name.characters.first,
        style: TextStyle(color: cs.onSecondaryContainer),
      ),
    ),
    title: Row(
      children: [
        Flexible(
          child: Text(
            it.name.isEmpty ? it.urls.first : it.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (it.master) ...[
          const SizedBox(width: 6),
          _tag(
            Lc.current.siteMaster,
            cs.tertiaryContainer,
            cs.onTertiaryContainer,
          ),
        ],
      ],
    ),
    subtitle: it.desc.isEmpty
        ? null
        : Text(it.desc, maxLines: 2, overflow: TextOverflow.ellipsis),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: () => _open(it),
  );

  Widget _empty(ColorScheme cs) => EmptyView(
    // 下拉刷新要有可滚的东西，空态也得能拉。
    icon: Icons.public_off_rounded,
    title: Lc.current.siteCatalogEmpty,
    hint: _err == null
        ? Lc.current.siteCatalogEmptyHint
        : errorText(context, _err!),
    error: _err != null,
  ).scrollable();

  Widget _tag(String text, Color bg, Color fg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(text, style: TextStyle(fontSize: 11, color: fg)),
  );
}
