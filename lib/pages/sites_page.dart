import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../api.dart';
import '../site_meta.dart';
import '../sites.dart';
import '../store.dart';

import '../l10n/error_text.dart';
import '../l10n/l10n.dart';
/// 站点管理：本机站点表。加、删、切、设登录站，以及清单导入。
///
/// 这里的规矩：
/// - 连不上的站标灰，不弹窗骂人——地址多、网络乱是常态；
/// - 删除只删本机这一行，账号和帖子在对方服务器上；
/// - 注册/登录/找回密码只发登录站，所以在哪座站上都标得出来。
class SitesPage extends StatefulWidget {
  const SitesPage({super.key});

  @override
  State<SitesPage> createState() => _SitesPageState();
}

class _SitesPageState extends State<SitesPage> {
  /// 切换或导入进行中，避免连点。
  bool _busy = false;

  /// 批量探测进行中。和 [_busy] 分开：导入完成时会顺手探一遍，两者会重叠。
  bool _probing = false;

  AppState get _st => AppState.instance;

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 逐座站探一遍，只更新标灰状态，不动当前出口。
  Future<void> _probeAll() async {
    if (_probing) return;
    _probing = true;
    if (mounted) setState(() {});
    try {
      for (final s in List<SiteEntry>.of(_st.sites)) {
        final ok = await Api.probeAt(s.orderedUrls, mark: false);
        s.reachable = ok != null;
        if (ok != null) s.lastOk = ok;
        if (!mounted) return;
        setState(() {});
      }
    } finally {
      _probing = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _switchTo(SiteEntry s) async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await _st.switchSite(s);
    if (!mounted) return;
    setState(() => _busy = false);
    _toast(ok ? Lc.current.switchedTo(s.display) : Lc.current.connectFailedBody(s.display));
  }

  Future<void> _setLogin(SiteEntry s) async {
    await _st.setLoginSite(s);
    _toast(Lc.current.siteLoginSet(s.display));
  }

  Future<void> _remove(SiteEntry s) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(Lc.current.siteRemoveConfirm(s.display)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(Lc.current.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(Lc.current.delete),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await _st.removeSite(s);
  }

  /// 手填一个地址。读到 /meta 后名字和入口会被自动补齐。
  Future<void> _addManual() async {
    final ctrl = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Lc.current.siteAdd),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: InputDecoration(
            hintText: 'http://192.168.1.10:8080',
            helperText: Lc.current.siteAddHint,
            helperMaxLines: 3,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(Lc.current.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            child: Text(Lc.current.add),
          ),
        ],
      ),
    );
    ctrl.dispose();
    final v = normalizeUrl(url ?? '');
    if (v.isEmpty) return;
    setState(() => _busy = true);
    final added = await _st.addSites([SiteEntry(urls: [v])]);
    // 新加的这座马上探一次，顺手把它切过去——刚填完地址就是想看它。
    SiteEntry? hit;
    for (final s in _st.sites) {
      if (s.urls.contains(v)) hit = s;
    }
    if (hit != null) {
      if (added > 0 || _st.activeKey.isEmpty) {
        await _st.switchSite(hit);
      } else {
        await _probeOne(hit);
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _probeOne(SiteEntry s) async {
    final ok = await Api.probeAt(s.orderedUrls, mark: false);
    s.reachable = ok != null;
    if (mounted) setState(() {});
  }

  /// 粘贴一份清单（一个文件多座站）或从主站拉目录，都走这里。
  Future<void> _import(Object? raw) async {
    final dropped = <Map<String, String>>[];
    final list = SiteMeta.parseManifest(raw, dropped: dropped);
    if (list.isEmpty) {
      _toast(
        dropped.isEmpty
            ? Lc.current.siteImportEmpty
            : Lc.current.siteImportNone(_skipText(dropped)),
      );
      return;
    }
    final added = await _st.addSites(
      list.map((m) => SiteEntry.fromMeta(m)).toList(),
    );
    if (!mounted) return;
    if (dropped.isEmpty) {
      _toast(Lc.current.siteImported('$added'));
    } else {
      _toast(
        Lc.current.siteImportedSkipped(
          '$added',
          '${dropped.length}',
          _skipText(dropped),
        ),
      );
    }
    // 导入完顺手把新来的站标灰/标通，界面上能立刻看出哪座活着。
    unawaited(_probeAll());
  }

  /// `[{"reason":"no_url"},…]` → `没有地址 2、id 重复 1`
  String _skipText(List<Map<String, String>> dropped) {
    final count = <String, int>{};
    for (final d in dropped) {
      final r = d['reason'] ?? 'bad_format';
      count[r] = (count[r] ?? 0) + 1;
    }
    return count.entries
        .map((e) => '${_skipReason(e.key)} ${e.value}')
        .join(Lc.current.listSep);
  }

  String _skipReason(String r) => switch (r) {
    'no_url' => Lc.current.skipNoUrl,
    'duplicate_id' => Lc.current.skipDuplicateId,
    'api_too_new' => Lc.current.skipApiTooNew,
    _ => Lc.current.skipBadFormat,
  };

  Future<void> _pasteManifest() async {
    final ctrl = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Lc.current.siteImportPaste),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: ctrl,
            autofocus: true,
            maxLines: 10,
            minLines: 6,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            decoration: InputDecoration(
              hintText: '{"schema":1,"sites":[{"url":"http://…"}]}',
              helperText: Lc.current.siteImportPasteHint,
              helperMaxLines: 3,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(Lc.current.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            child: Text(Lc.current.importIt),
          ),
        ],
      ),
    );
    ctrl.dispose();
    final t = (text ?? '').trim();
    if (t.isEmpty) return;
    Object? raw;
    try {
      raw = jsonDecode(t);
    } catch (e) {
      _toast(Lc.current.siteImportFailed('$e'));
      return;
    }
    await _import(raw);
  }

  /// 从登录站拉目录：`GET /api/sites`，格式和 bbs.json 一样，直接导入。
  Future<void> _importFromMaster() async {
    final urls = _st.loginUrls;
    if (urls.isEmpty) {
      _toast(Lc.current.errNotConfigured);
      return;
    }
    setState(() => _busy = true);
    try {
      final raw = await Api.getAt(urls, '/sites');
      await _import(raw);
    } on ApiException catch (e) {
      if (mounted) _toast(errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _st,
      builder: (context, _) {
        final sites = _st.sites;
        return Scaffold(
          appBar: AppBar(
            title: Text(Lc.current.sitesManage),
            actions: [
              if (_busy || _probing)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Center(
                    child: SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else
                IconButton(
                  tooltip: Lc.current.siteProbe,
                  icon: const Icon(Icons.refresh),
                  onPressed: _probeAll,
                ),
              PopupMenuButton<String>(
                onSelected: (v) async {
                  switch (v) {
                    case 'add':
                      await _addManual();
                    case 'paste':
                      await _pasteManifest();
                    case 'master':
                      await _importFromMaster();
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'add',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.add),
                      title: Text(Lc.current.siteAdd),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'paste',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.content_paste),
                      title: Text(Lc.current.siteImportPaste),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'master',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.cloud_download_outlined),
                      title: Text(Lc.current.siteImportMaster),
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: sites.isEmpty
              ? _empty(cs)
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 32),
                  itemCount: sites.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) => _tile(sites[i], cs),
                ),
          floatingActionButton: sites.isEmpty
              ? null
              : FloatingActionButton.extended(
                  onPressed: _busy ? null : _addManual,
                  icon: const Icon(Icons.add),
                  label: Text(Lc.current.siteAdd),
                ),
        );
      },
    );
  }

  Widget _empty(ColorScheme cs) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.dns_outlined, size: 56, color: cs.outline),
          const SizedBox(height: 16),
          Text(
            Lc.current.siteEmpty,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            Lc.current.siteEmptyHint,
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _busy ? null : _addManual,
            icon: const Icon(Icons.add),
            label: Text(Lc.current.siteAdd),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _busy ? null : _importFromMaster,
            icon: const Icon(Icons.cloud_download_outlined),
            label: Text(Lc.current.siteImportMaster),
          ),
        ],
      ),
    ),
  );

  Widget _tile(SiteEntry s, ColorScheme cs) {
    final active = s.key == _st.activeKey;
    final down = s.reachable == false;
    // 三种状态：没探过是空心灰，通了是主色，连不上是暗色加一行字。
    final dot = switch (s.reachable) {
      true => cs.primary,
      false => cs.outline,
      null => cs.outlineVariant,
    };
    final host = s.host.isEmpty ? s.primary : s.host;
    return ListTile(
      enabled: !down,
      onTap: _busy ? null : () => active ? _probeOne(s) : _switchTo(s),
      leading: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              s.display,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: down ? cs.outline : null,
                fontWeight: active ? FontWeight.w600 : null,
              ),
            ),
          ),
          if (s.master) ...[
            const SizedBox(width: 6),
            _tag(Lc.current.siteLoginSite, cs.secondaryContainer, cs.onSecondaryContainer),
          ],
          if (active) ...[
            const SizedBox(width: 6),
            _tag(Lc.current.siteCurrentNow, cs.primaryContainer, cs.onPrimaryContainer),
          ],
        ],
      ),
      subtitle: Text(
        down ? '$host · ${Lc.current.siteUnreachable}' : host,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: down ? cs.error : cs.onSurfaceVariant, fontSize: 12),
      ),
      trailing: PopupMenuButton<String>(
        enabled: !_busy,
        onSelected: (v) async {
          switch (v) {
            case 'switch':
              await _switchTo(s);
            case 'login':
              await _setLogin(s);
            case 'remove':
              await _remove(s);
          }
        },
        itemBuilder: (_) => [
          if (!active)
            PopupMenuItem(
              value: 'switch',
              child: Text(Lc.current.siteSwitch),
            ),
          if (!s.master)
            PopupMenuItem(
              value: 'login',
              child: Text(Lc.current.siteSetLogin),
            ),
          PopupMenuItem(
            value: 'remove',
            child: Text(
              Lc.current.delete,
              style: TextStyle(color: cs.error),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tag(String text, Color bg, Color fg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
    child: Text(text, style: TextStyle(fontSize: 11, color: fg)),
  );
}
