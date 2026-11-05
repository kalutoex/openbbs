import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api.dart';
import '../notify.dart';
import '../site_config.dart';
import '../cache_clear.dart';
import '../store.dart';
import 'account_security_page.dart';
import '../update.dart';
import '../update_prompt.dart';
import 'about_page.dart';
import 'accounts_page.dart';
import 'cloud_settings_page.dart';
import 'permissions_page.dart';
import 'sites_page.dart';
import 'theme_color_page.dart';

import '../l10n/error_text.dart';
import '../l10n/l10n.dart';
import '../widgets/page_width.dart';
import '../widgets/toast.dart';

/// 设置：外观、浏览、云服务、网络、内容、账号、关于。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final st = AppState.instance;

    return Scaffold(
      appBar: AppBar(title: Text(Lc.current.settings)),
      body: PageWidth(
        child: ListenableBuilder(
          listenable: st,
          builder: (context, _) {
            final u = st.user;
            return ListView(
              padding: const EdgeInsets.only(bottom: 40),
              children: [
                _label(context, Lc.current.appearance),
                ValueListenableBuilder<ThemeMode>(
                  valueListenable: st.themeMode,
                  builder: (_, m, _) => _row(
                    context,
                    icon: Icons.dark_mode_outlined,
                    title: Lc.current.theme,
                    value: _themeName(m),
                    onTap: () => _pickTheme(context),
                  ),
                ),
                ValueListenableBuilder<double>(
                  valueListenable: st.accentHue,
                  builder: (_, h, _) => _row(
                    context,
                    icon: Icons.palette_outlined,
                    title: Lc.current.accentColor,
                    value: AppState.hueName(h),
                    dot: st.colorOfHue(h),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ThemeColorPage()),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                _label(context, Lc.current.browseSection),
                ValueListenableBuilder<String>(
                  valueListenable: st.feedSort,
                  builder: (_, v, _) => _row(
                    context,
                    icon: Icons.sort,
                    title: Lc.current.feedSort,
                    value: v == 'created'
                        ? Lc.current.sortCreated
                        : Lc.current.sortUpdated,
                    onTap: () => _pickSort(context),
                  ),
                ),
                ValueListenableBuilder<int>(
                  valueListenable: st.startTab,
                  builder: (_, v, _) => _row(
                    context,
                    icon: Icons.home_outlined,
                    title: Lc.current.startTab,
                    subtitle: Lc.current.startTabHint,
                    value: _tabName(v),
                    onTap: () => _pickStartTab(context),
                  ),
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: st.thumbs,
                  builder: (_, v, _) => SwitchListTile(
                    secondary: const Icon(Icons.image_outlined),
                    title: Text(Lc.current.showThumbnails),
                    subtitle: Text(Lc.current.showThumbnailsHint),
                    value: v,
                    onChanged: (x) => st.setThumbs(x),
                  ),
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: st.autoUnread,
                  builder: (_, v, _) => SwitchListTile(
                    secondary: const Icon(Icons.notifications_active_outlined),
                    title: Text(Lc.current.autoCheckNotice),
                    subtitle: Text(Lc.current.autoCheckNoticeHint),
                    value: v,
                    onChanged: (x) => st.setAutoUnread(x),
                  ),
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: st.sysNotify,
                  builder: (ctx, v, _) => SwitchListTile(
                    secondary: const Icon(Icons.notification_add_outlined),
                    title: Text(Lc.current.sysNotify),
                    subtitle: Text(Lc.current.sysNotifyHint),
                    value: v,
                    onChanged: (x) async {
                      await st.setSysNotify(x);
                      // 打开时顺手要权限；系统那边拒绝过的话这里要不到，
                      // 得当场说一声，不然他以为开关一拨就能收到。
                      if (!x) return;
                      final ok = await SysNotify.ask();
                      if (!ok && ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(content: Text(Lc.current.sysNotifyOff)),
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(height: 6),
                _label(context, Lc.current.cloudSection),
                ListTile(
                  leading: const Icon(Icons.cloud_outlined),
                  title: Text(Lc.current.cloudSettings),
                  subtitle: Text(Lc.current.cloudSettingsHint),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const CloudSettingsPage(),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                _label(context, Lc.current.networkSection),
                _row(
                  context,
                  icon: Icons.dns_outlined,
                  title: Lc.current.sitesManage,
                  subtitle: st.sites.isEmpty
                      ? Lc.current.siteEmptyHint
                      : '${st.activeSite?.display ?? ''} · ${st.sites.length}',
                  value: _siteSummary(st),
                  onTap: () => Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => const SitesPage())),
                ),
                const SizedBox(height: 6),
                _label(context, Lc.current.contentSection),
                const _ClearCacheTile(),
                ListTile(
                  leading: const Icon(Icons.verified_user_outlined),
                  title: Text(Lc.current.permissions),
                  subtitle: Text(Lc.current.permSubtitle),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PermissionsPage()),
                  ),
                ),
                const SizedBox(height: 6),
                _label(context, Lc.current.accounts),
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(Lc.current.currentAccount),
                  subtitle: Text(
                    st.accounts.length > 1
                        ? Lc.current.accountLine(
                            u == null
                                ? Lc.current.notLoggedIn
                                : (u['nickname'] ?? u['name'] ?? ''),
                            '${st.accounts.length}',
                          )
                        : (u == null
                              ? Lc.current.notLoggedIn
                              : '${u['nickname'] ?? u['name']}'),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AccountsPage()),
                  ),
                ),
                if (u != null)
                  ListTile(
                    leading: const Icon(Icons.lock_outline),
                    title: Text(Lc.current.accountSecurity),
                    subtitle: Text(
                      ((u['email'] as String?) ?? '').isEmpty
                          ? Lc.current.noEmailBoundHint
                          : (u['email'] as String),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const AccountSecurityPage(),
                      ),
                    ),
                  ),
                if (u != null)
                  ListTile(
                    leading: Icon(Icons.logout, color: cs.error),
                    title: Text(
                      Lc.current.logout,
                      style: TextStyle(color: cs.error),
                    ),
                    onTap: () => _logout(context),
                  ),
                const SizedBox(height: 6),
                if (kIsWeb) ...[
                  _label(context, Lc.current.webAccessSection),
                  const _WebEntryRow(),
                ],
                _label(context, Lc.current.about),
                const _VersionRow(),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(Lc.current.aboutBrand('${SiteConfig.brand}')),
                  subtitle: Text(Lc.current.aboutSubtitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => const AboutPage())),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 分组标题：小、灰、跟下面留一点空。
  ///
  /// 原来用主色 + 全宽分割线，一屏下来绿线和灰字打架，
  /// 现在靠留白分组，标题只做定位不做装饰。
  static Widget _label(BuildContext context, String s) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
    child: Text(
      s,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        color: Theme.of(context).colorScheme.outline,
      ),
    ),
  );

  static Widget _row(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
    required String value,
    Color? dot,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot != null) ...[
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: dot,
                shape: BoxShape.circle,
                border: Border.all(color: cs.outlineVariant, width: 1.5),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(value, style: TextStyle(color: cs.outline, fontSize: 13)),
        ],
      ),
      onTap: onTap,
    );
  }

  static String _themeName(ThemeMode m) => switch (m) {
    ThemeMode.system => Lc.current.themeSystem,
    ThemeMode.light => Lc.current.themeLight,
    ThemeMode.dark => Lc.current.themeDark,
  };

  static String _tabName(int v) => switch (v) {
    1 => Lc.current.sites,
    2 => Lc.current.notice,
    3 => Lc.current.me,
    _ => Lc.current.home,
  };

  /// 站点管理这一行只交代「用哪座站」。地址那一串在列表里看得到，
  /// 摆在这儿又长又没信息量。
  static String _siteSummary(AppState st) {
    final m = st.masterSite;
    final name = (m ?? st.activeSite)?.display ?? '';
    if (name.isEmpty) return '';
    return m == null ? name : '${Lc.current.siteMaster}（$name）';
  }

  Future<void> _pickTheme(BuildContext ctx) async {
    final st = AppState.instance;
    final cur = st.themeMode.value;
    final v = await showDialog<ThemeMode>(
      context: ctx,
      builder: (c) => _pickDialog<ThemeMode>(
        title: Lc.current.theme,
        current: cur,
        options: [for (final m in ThemeMode.values) (m, _themeName(m))],
      ),
    );
    if (v != null) await st.setThemeMode(v);
  }

  Future<void> _pickSort(BuildContext ctx) async {
    final st = AppState.instance;
    final cur = st.feedSort.value;
    final v = await showDialog<String>(
      context: ctx,
      builder: (c) => _pickDialog<String>(
        title: Lc.current.feedSort,
        current: cur,
        options: [
          ('updated', Lc.current.sortUpdated),
          ('created', Lc.current.sortCreated),
        ],
      ),
    );
    if (v != null) await st.setFeedSort(v);
  }

  Future<void> _pickStartTab(BuildContext ctx) async {
    final st = AppState.instance;
    final cur = st.startTab.value;
    final v = await showDialog<int>(
      context: ctx,
      builder: (c) => _pickDialog<int>(
        title: Lc.current.startTab,
        current: cur,
        options: [
          (0, Lc.current.home),
          (2, Lc.current.notice),
          (3, Lc.current.me),
        ],
      ),
    );
    if (v != null) await st.setStartTab(v);
  }

  Future<void> _logout(BuildContext ctx) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(
        title: Text(Lc.current.confirmLogout),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(Lc.current.forgetIt),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(Lc.current.logoutShort),
          ),
        ],
      ),
    );
    if (ok == true) await AppState.instance.logout();
  }
}

/// 单选弹窗：当前项打勾。
Widget _pickDialog<T>({
  required String title,
  required T current,
  required List<(T, String)> options,
}) {
  return SimpleDialog(
    title: Text(title),
    children: [
      for (final o in options)
        Builder(
          builder: (c) => SimpleDialogOption(
            onPressed: () => Navigator.pop(c, o.$1),
            child: Row(
              children: [
                Icon(
                  o.$1 == current
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Text(o.$2),
              ],
            ),
          ),
        ),
    ],
  );
}

/// 版本行：点一下去服务器问有没有新包，有就下下来交给系统安装。
class _VersionRow extends StatefulWidget {
  const _VersionRow();

  @override
  State<_VersionRow> createState() => _VersionRowState();
}

class _VersionRowState extends State<_VersionRow> {
  static const _kBeta = 'update_beta';

  PackageInfo? _pkg;
  bool? _beta; // null：没手动选过

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((p) {
      if (mounted) setState(() => _pkg = p);
    });
    SharedPreferences.getInstance().then((sp) {
      if (mounted) setState(() => _beta = sp.getBool(_kBeta));
    });
  }

  bool get _isAdmin => AppState.instance.user?['is_admin'] == true;

  /// 没手动选过就按身份走：管理员默认收内测，其他人收稳定版。
  bool get _useBeta => _beta ?? _isAdmin;

  Future<void> _setBeta(bool v) async {
    setState(() => _beta = v);
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kBeta, v);
  }

  @override
  Widget build(BuildContext context) {
    final p = _pkg;
    final text = p == null ? '…' : '${p.version} (${p.buildNumber})';
    final row = ListTile(
      leading: const Icon(Icons.system_update_alt),
      title: Text(Lc.current.version),
      subtitle: Text(Lc.current.tapToCheckUpdate),
      trailing: Text(text, style: const TextStyle(fontSize: 13)),
      // 取不到自身版本号也让点：真检查不出来，至少还能问服务器一趟。
      onTap: _check,
    );
    if (!_isAdmin) return row;
    return Column(
      children: [
        row,
        ListTile(
          leading: const Icon(Icons.science_outlined),
          title: Text(Lc.current.updateChannel),
          subtitle: Text(
            _useBeta
                ? Lc.current.betaChannelHint
                : Lc.current.stableChannelHint,
          ),
          trailing: const Icon(Icons.chevron_right, size: 20),
          onTap: _pickChannel,
        ),
      ],
    );
  }

  Future<void> _pickChannel() async {
    final v = await showDialog<bool>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text(Lc.current.updateChannel),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, false),
            child: Text(Lc.current.stableOption),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, true),
            child: Text(Lc.current.betaOption),
          ),
        ],
      ),
    );
    if (v == null || !mounted) return;
    await _setBeta(v);
  }

  int get _localBuild => int.tryParse(_pkg?.buildNumber ?? '') ?? 0;

  Future<void> _check() async {
    AppRelease? rel;
    // 先把异常存下来，等确认还活着再用 context 翻译。
    Object? err;
    try {
      rel = await fetchLatest(beta: _useBeta);
    } on ApiException catch (e) {
      err = e;
    } catch (_) {
      err = Lc.current.connectFailedPlain;
    }
    if (!mounted) return;

    if (err != null) {
      await _tell(
        Lc.current.checkUpdate,
        err is String ? err : errorText(context, err),
      );
      return;
    }
    final r = rel!;
    if (r.build == _localBuild) {
      await _tell(
        Lc.current.checkUpdate,
        Lc.current.upToDate('${_pkg?.version ?? ''}'),
      );
      return;
    }
    if (r.build < _localBuild) {
      await _tell(
        Lc.current.checkUpdate,
        Lc.current.newerThanServer(
          '$_localBuild',
          r.channel == 'beta' ? Lc.current.betaShort : Lc.current.stableShort,
          '${r.build}',
        ),
      );
      return;
    }

    if (!mounted) return;
    final go = await showUpdatePrompt(context, r, current: _pkg);
    if (go && mounted) await installApk(context, r);
  }

  Future<void> _tell(String title, String body) {
    return showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(Lc.current.ok),
          ),
        ],
      ),
    );
  }
}

/// 网页端的两个入口：当前地址和另一个端口，都能一键复制。
class _WebEntryRow extends StatelessWidget {
  const _WebEntryRow();

  static String _fmt(Uri u) => u.port == 0
      ? '${u.scheme}://${u.host}'
      : '${u.scheme}://${u.host}:${u.port}';

  static String get _current => _fmt(Uri.base);

  /// 备用入口：构建时配了第二个服务器就显示它，没有就返回空。
  /// 以前是按域名前缀硬推「IPv6 那个 / frp 那个」，换域名就得改代码。
  static String get _alt {
    final cur = _current;
    for (final s in SiteConfig.servers) {
      final u = Uri.tryParse(s);
      if (u == null) continue;
      final f = _fmt(u);
      if (f != cur) return f;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.link),
          title: Text(Lc.current.primaryEndpoint),
          subtitle: Text(_current, style: const TextStyle(fontSize: 12)),
          trailing: const Icon(Icons.copy, size: 18),
          onTap: () => _copy(context, _current),
        ),
        if (_alt.isNotEmpty) ...[
          ListTile(
            leading: const Icon(Icons.swap_horiz),
            title: Text(Lc.current.backupEndpoint),
            subtitle: Text(_alt, style: const TextStyle(fontSize: 12)),
            trailing: const Icon(Icons.copy, size: 18),
            onTap: () => _copy(context, _alt),
          ),
        ],
      ],
    );
  }

  void _copy(BuildContext context, String s) {
    Clipboard.setData(ClipboardData(text: s));
    toast(context, Lc.current.addressCopied);
  }
}

/// 清缓存。大小等点进设置页才去算，省得每次进设置都扫一遍目录。
class _ClearCacheTile extends StatefulWidget {
  const _ClearCacheTile();

  @override
  State<_ClearCacheTile> createState() => _ClearCacheTileState();
}

class _ClearCacheTileState extends State<_ClearCacheTile> {
  int? _size;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await AppCache.size();
    if (!mounted) return;
    setState(() => _size = s);
  }

  Future<void> _confirm() async {
    if (_busy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(Lc.current.clearCache),
        content: Text(Lc.current.clearCacheConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(Lc.current.forgetIt),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(Lc.current.clear),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final before = _size ?? 0;
    setState(() => _busy = true);
    await AppCache.clear();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _size = 0;
    });
    toast(
      context,
      before > 0
          ? Lc.current.clearedAmount('${AppCache.human(before)}')
          : Lc.current.cleared,
    );
  }

  @override
  Widget build(BuildContext context) {
    final sub = _busy
        ? Lc.current.clearing
        : _size == null
        ? Lc.current.calculating
        : _size == 0
        ? Lc.current.cacheEmpty
        : Lc.current.cacheSize('${AppCache.human(_size!)}');
    return ListTile(
      leading: const Icon(Icons.cleaning_services_outlined),
      title: Text(Lc.current.clearCache),
      subtitle: Text(sub),
      onTap: _confirm,
    );
  }
}
