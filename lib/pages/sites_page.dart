import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../api.dart';
import '../site_meta.dart';
import '../sites.dart';
import '../store.dart';

import '../l10n/error_text.dart';
import '../l10n/l10n.dart';
import '../widgets/empty_view.dart';
import '../widgets/app_card.dart';
import '../widgets/toast.dart';

/// 站点管理：本机站点表。加、删、切、设登录站，以及清单导入。
///
/// 这里的规矩：
/// - 主站（时间线）是兜底，不给删；发帖只能发到主站或小站；
/// - 不对外露网址：用户只需要知道 v6 / v4 哪条通、多少毫秒；
/// - 连不上的站标灰，不弹窗骂人——地址多、网络乱是常态；
/// - 删除只删本机这一行，账号和帖子在对方服务器上；
/// - 注册/登录/找回密码只发登录站，所以在哪座站上都标得出来。
class SitesPage extends StatefulWidget {
  /// 当底部 tab 用时把抽屉按钮挂上；从设置页进来是 null，走默认返回键。
  final VoidCallback? onMenu;

  /// 切站成功后回调，底部 tab 用它跳回时间线。
  final VoidCallback? onSwitched;

  const SitesPage({super.key, this.onMenu, this.onSwitched});

  @override
  State<SitesPage> createState() => _SitesPageState();
}

class _SitesPageState extends State<SitesPage> {
  /// 切换或导入进行中，避免连点。
  bool _busy = false;

  /// 批量探测进行中。和 [_busy] 分开：导入完成时会顺手探一遍，两者会重叠。
  bool _probing = false;

  /// 测速进行中。只挡那条路线上的重复点击，不冻整个列表。
  final Set<String> _testing = <String>{};

  AppState get _st => AppState.instance;

  void _toast(String msg) {
    if (!mounted) return;
    toast(context, msg);
  }

  /// 测速：长按某座站就跑一遍，回每条入口的毫秒数。
  ///
  /// 结果顺手写回 epStatus，测完这一行的 v6 / v4 通不通也一起刷新了。
  Future<void> _speedTest(SiteEntry s) async {
    if (_testing.contains(s.key)) return;
    _testing.add(s.key);
    _toast(Lc.current.siteSpeedRunning);
    if (mounted) setState(() {});
    try {
      final ms = await Api.speedTest(s.orderedUrls);
      s.epMs
        ..clear()
        ..addAll(ms);
      for (final u in s.orderedUrls) {
        s.epStatus[u] = ms.containsKey(u);
      }
      final ok = ms.isNotEmpty;
      s.reachable = ok;
      if (ok) {
        s.lastOk = ms.keys.first;
      }
      if (!mounted) return;
      setState(() {});
      final parts = <String>[
        for (final e in ms.entries)
          '${looksV6(e.key) ? 'IPv6' : 'IPv4'} ${e.value}ms',
      ];
      _toast(
        Lc.current.siteSpeedResult(
          parts.isEmpty ? Lc.current.siteSpeedNone : parts.join(' · '),
        ),
      );
    } finally {
      _testing.remove(s.key);
      if (mounted) setState(() {});
    }
  }

  /// 逐座站探一遍，只更新标灰状态，不动当前出口。
  Future<void> _probeAll() async {
    if (_probing) return;
    _probing = true;
    if (mounted) setState(() {});
    try {
      for (final s in List<SiteEntry>.of(_st.sites)) {
        final rep = await Api.probeReport(s.orderedUrls);
        s.epStatus
          ..clear()
          ..addAll(rep);
        s.epMs.clear();
        String? ok;
        for (final e in rep.entries) {
          if (e.value) {
            ok = e.key;
            break;
          }
        }
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
    // 切完把每条入口各自的结果补上：v6 通、v4 不通这种事得看得见。
    await _probeOne(s);
    if (!mounted) return;
    setState(() => _busy = false);
    _toast(
      ok
          ? Lc.current.switchedTo(s.display)
          : Lc.current.connectFailedBody(s.display),
    );
    if (ok) widget.onSwitched?.call();
  }

  Future<void> _setLogin(SiteEntry s) async {
    await _st.setLoginSite(s);
    _toast(Lc.current.siteLoginSet(s.display));
  }

  Future<void> _remove(SiteEntry s) async {
    // 主站不给删：删完就只剩小站，发帖的兜底没了。
    if (s.isHome) {
      _toast(Lc.current.siteMasterFixed);
      return;
    }
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
    final added = await _st.addSites([
      SiteEntry(urls: [v]),
    ]);
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
    final rep = await Api.probeReport(s.orderedUrls);
    s.epStatus
      ..clear()
      ..addAll(rep);
    // 探路不带耗时，旧数字留着会骗人。
    s.epMs.clear();
    String? ok;
    for (final e in rep.entries) {
      if (e.value) {
        ok = e.key;
        break;
      }
    }
    s.reachable = ok != null;
    if (ok != null) s.lastOk = ok;
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
            leading: widget.onMenu == null
                ? null
                : IconButton(
                    onPressed: widget.onMenu,
                    icon: const Icon(Icons.menu),
                    tooltip: Lc.current.menu,
                  ),
            title: Text(
              widget.onMenu == null ? Lc.current.sitesManage : Lc.current.sites,
            ),
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
              ? _empty()
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 96),
                  itemCount: sites.length,
                  itemBuilder: (_, i) => AppCard(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: _tile(sites[i], cs),
                  ),
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

  Widget _empty() => EmptyView(
    icon: Icons.dns_outlined,
    title: Lc.current.siteEmpty,
    hint: Lc.current.siteEmptyHint,
    action: Column(
      children: [
        FilledButton.icon(
          onPressed: _busy ? null : _addManual,
          icon: const Icon(Icons.add),
          label: Text(Lc.current.siteAdd),
        ),
        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: _busy ? null : _importFromMaster,
          icon: const Icon(Icons.cloud_download_outlined),
          label: Text(Lc.current.siteImportMaster),
        ),
      ],
    ),
  );

  /// 这一行能做的事：切过去、设成登录站、删掉。
  ///
  /// 主站不出删除项——删完就只剩小站，发帖的兜底没了。
  List<PopupMenuEntry<String>> _actions(
    SiteEntry s, {
    required bool active,
    required bool home,
    required ColorScheme cs,
  }) => [
    if (!active)
      PopupMenuItem(value: 'switch', child: Text(Lc.current.siteSwitch)),
    if (!s.master)
      PopupMenuItem(value: 'login', child: Text(Lc.current.siteSetLogin)),
    if (!home)
      PopupMenuItem(
        value: 'block',
        child: Text(s.blocked ? Lc.current.siteUnblock : Lc.current.siteBlock),
      ),
    if (!home)
      PopupMenuItem(
        value: 'remove',
        child: Text(Lc.current.delete, style: TextStyle(color: cs.error)),
      ),
  ];

  Future<void> _toggleBlock(SiteEntry s) async {
    await AppState.instance.toggleBlocked(s);
    if (!mounted) return;
    _toast(
      s.blocked ? Lc.current.siteBlockedDone : Lc.current.siteUnblockedDone,
    );
  }

  Widget _tile(SiteEntry s, ColorScheme cs) {
    final active = s.key == _st.activeKey;
    final home = s.isHome;
    final down = s.reachable == false;
    // 三种状态：没探过是空心灰，通了是主色，连不上是暗色。
    final dot = switch (s.reachable) {
      true => cs.primary,
      false => cs.outline,
      null => cs.outlineVariant,
    };
    return ListTile(
      // 点一下：当前站就重探，别的站就切过去。
      onTap: _busy ? null : () => active ? _probeOne(s) : _switchTo(s),
      // 长按测速。主站也好小站也好，测的都是这座站的入口。
      onLongPress: _testing.contains(s.key) ? null : () => _speedTest(s),
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
          const SizedBox(width: 6),
          // 主站 / 小站：发帖时只能选这两类，列表上先标清楚。
          home
              ? _tag(
                  Lc.current.siteMaster,
                  cs.tertiaryContainer,
                  cs.onTertiaryContainer,
                )
              : _tag(
                  Lc.current.siteSmall,
                  cs.surfaceContainerHighest,
                  cs.onSurfaceVariant,
                ),
          if (s.master) ...[
            const SizedBox(width: 6),
            _tag(
              Lc.current.siteLoginSite,
              cs.secondaryContainer,
              cs.onSecondaryContainer,
            ),
          ],
          if (active) ...[
            const SizedBox(width: 6),
            _tag(
              Lc.current.siteCurrentNow,
              cs.primaryContainer,
              cs.onPrimaryContainer,
            ),
          ],
          if (s.blocked) ...[
            const SizedBox(width: 6),
            _tag(
              Lc.current.siteBlocked,
              cs.errorContainer,
              cs.onErrorContainer,
            ),
          ],
        ],
      ),
      subtitle: Wrap(
        spacing: 6,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // 只报通不通：网址是给运维看的，用户只需要知道哪条路走着。
          for (final u in s.orderedUrls)
            _epChip(u, s.epStatus[u], s.epMs[u], cs),
          if (down)
            Text(
              Lc.current.siteUnreachable,
              style: TextStyle(color: cs.error, fontSize: 12),
            ),
          if (_testing.contains(s.key))
            Text(
              Lc.current.siteSpeedRunning,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
        ],
      ),
      // 主站既是当前站又是登录站时三项全被过滤，那就别挂按钮——
      // 点开一个空菜单比没有按钮更让人犯嘀咕。
      trailing: _actions(s, active: active, home: home, cs: cs).isEmpty
          ? null
          : PopupMenuButton<String>(
              enabled: !_busy,
              onSelected: (v) async {
                switch (v) {
                  case 'switch':
                    await _switchTo(s);
                  case 'login':
                    await _setLogin(s);
                  case 'block':
                    await _toggleBlock(s);
                  case 'remove':
                    await _remove(s);
                }
              },
              itemBuilder: (_) =>
                  _actions(s, active: active, home: home, cs: cs),
            ),
    );
  }

  /// 单条入口的状态标记：`IPv6 ✓ 32ms` / `IPv4 ✗`，没探过只显示名字。
  Widget _epChip(String url, bool? ok, int? ms, ColorScheme cs) {
    final label = looksV6(url) ? 'IPv6' : 'IPv4';
    final text = switch (ok) {
      true => ms == null ? '$label ✓' : '$label ✓ ${ms}ms',
      false => '$label ✗',
      null => label,
    };
    final bg = switch (ok) {
      true => cs.primaryContainer,
      false => cs.errorContainer,
      null => cs.surfaceContainerHighest,
    };
    final fg = switch (ok) {
      true => cs.onPrimaryContainer,
      false => cs.onErrorContainer,
      null => cs.onSurfaceVariant,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: TextStyle(fontSize: 11, color: fg)),
    );
  }

  Widget _tag(String text, Color bg, Color fg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(text, style: TextStyle(fontSize: 11, color: fg)),
  );
}
