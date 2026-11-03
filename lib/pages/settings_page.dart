import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api.dart';
import '../site_config.dart';
import '../cache_clear.dart';
import '../open_path.dart';
import '../plat.dart';
import '../store.dart';
import '../l10n/app_localizations.dart';
import 'account_security_page.dart';
import '../update.dart';
import 'about_page.dart';
import 'accounts_page.dart';
import 'permissions_page.dart';
import 'server_page.dart';
import 'theme_color_page.dart';

import '../l10n/error_text.dart';
import '../l10n/l10n.dart';
/// 设置：外观、浏览、内容、账号、关于。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final st = AppState.instance;

    return Scaffold(
      appBar: AppBar(title: Text(Lc.current.settings)),
      body: ListenableBuilder(
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
              ValueListenableBuilder<double>(
                valueListenable: st.fontScale,
                builder: (_, v, _) => _row(
                  context,
                  icon: Icons.format_size,
                  title: Lc.current.fontSize,
                  value: _fontName(v),
                  onTap: () => _pickFont(context),
                ),
              ),
              ValueListenableBuilder<int>(
                valueListenable: st.density,
                builder: (_, v, _) => _row(
                  context,
                  icon: Icons.view_agenda_outlined,
                  title: Lc.current.listDensity,
                  subtitle: Lc.current.threadSpacing,
                  value: _densityName(v),
                  onTap: () => _pickDensity(context),
                ),
              ),
              ValueListenableBuilder<String>(
                valueListenable: st.localeCode,
                builder: (_, v, _) => _row(
                  context,
                  icon: Icons.translate,
                  title: L.of(context).language,
                  value: _localeName(context, v),
                  onTap: () => _pickLocale(context),
                ),
              ),
              const Divider(height: 24),
              _label(context, Lc.current.browseSection),
              ValueListenableBuilder<String>(
                valueListenable: st.feedSort,
                builder: (_, v, _) => _row(
                  context,
                  icon: Icons.sort,
                  title: Lc.current.feedSort,
                  value: v == 'created' ? Lc.current.sortCreated : Lc.current.sortUpdated,
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
              const Divider(height: 24),
              _label(context, Lc.current.networkSection),
              _row(
                context,
                icon: Icons.dns_outlined,
                title: Lc.current.server,
                subtitle: Api.base,
                value: switch (st.serverMode) {
                  ServerMode.auto => Lc.current.auto,
                  ServerMode.ipv6 => 'IPv6',
                  ServerMode.ipv4 => 'IPv4',
                  ServerMode.manual => Lc.current.manual,
                },
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ServerPage()),
                ),
              ),
              const Divider(height: 24),
              _label(context, Lc.current.contentSection),
              const _ClearCacheTile(),
              ListTile(
                leading: const Icon(Icons.manage_search),
                title: Text(Lc.current.clearSearchHistory),
                onTap: () async {
                  final p = await SharedPreferences.getInstance();
                  await p.remove('search_hist');
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(Lc.current.searchHistoryCleared)));
                },
              ),
              ListTile(
                leading: const Icon(Icons.verified_user_outlined),
                title: Text(Lc.current.permissions),
                subtitle: Text(Lc.current.permSubtitle),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PermissionsPage()),
                ),
              ),
              const Divider(height: 24),
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
                          '${st.accounts.length}')
                      : (u == null ? Lc.current.notLoggedIn : '${u['nickname'] ?? u['name']}'),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const AccountsPage())),
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
                  leading: const Icon(Icons.key_outlined),
                  title: Text(Lc.current.copyCredential),
                  subtitle: Text(Lc.current.copyCredentialHint),
                  onTap: () async {
                    final t = Api.token;
                    if (t == null || t.isEmpty) return;
                    await Clipboard.setData(ClipboardData(text: t));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(Lc.current.credentialCopied)));
                  },
                ),
              if (u != null)
                ListTile(
                  leading: Icon(Icons.logout, color: cs.error),
                  title: Text(Lc.current.logout, style: TextStyle(color: cs.error)),
                  onTap: () => _logout(context),
                ),
              const Divider(height: 24),
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
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AboutPage()),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static Widget _label(BuildContext context, String s) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
    child: Text(
      s,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
        color: Theme.of(context).colorScheme.primary,
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

  static String _fontName(double v) =>
      v < 0.95 ? Lc.current.sizeSmall : (v > 1.25 ? Lc.current.sizeHuge : (v > 1.05 ? Lc.current.sizeLarge : Lc.current.densityNormal));

  static String _densityName(int v) => switch (v) {
    0 => Lc.current.densityCompact,
    2 => Lc.current.densityLoose,
    _ => Lc.current.densityNormal,
  };

  static String _tabName(int v) => switch (v) {
    1 => Lc.current.forums,
    2 => Lc.current.notice,
    3 => Lc.current.me,
    _ => Lc.current.timeline,
  };

  String _localeName(BuildContext c, String code) => switch (code) {
    'zh' => Lc.current.chinese,
    'en' => 'English',
    _ => L.of(c).languageSystem,
  };

  Future<void> _pickLocale(BuildContext ctx) async {
    final st = AppState.instance;
    final cur = st.localeCode.value;
    final v = await showDialog<String>(
      context: ctx,
      builder: (c) => _pickDialog<String>(
        title: L.of(c).language,
        current: cur,
        options: [
          ('', L.of(c).languageSystem),
          ('zh', Lc.current.chinese),
          ('en', 'English'),
        ],
      ),
    );
    if (v != null) await st.setLocale(v);
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

  Future<void> _pickFont(BuildContext ctx) async {
    final st = AppState.instance;
    final cur = st.fontScale.value;
    final v = await showDialog<double>(
      context: ctx,
      builder: (c) => _pickDialog<double>(
        title: Lc.current.fontSize,
        current: cur,
        options: [(0.9, Lc.current.sizeSmall), (1.0, Lc.current.densityNormal), (1.15, Lc.current.sizeLarge), (1.3, Lc.current.sizeHuge)],
      ),
    );
    if (v != null) await st.setFontScale(v);
  }

  Future<void> _pickDensity(BuildContext ctx) async {
    final st = AppState.instance;
    final cur = st.density.value;
    final v = await showDialog<int>(
      context: ctx,
      builder: (c) => _pickDialog<int>(
        title: Lc.current.listDensity,
        current: cur,
        options: [(0, Lc.current.densityCompact), (1, Lc.current.densityNormal), (2, Lc.current.densityLoose)],
      ),
    );
    if (v != null) await st.setDensity(v);
  }

  Future<void> _pickSort(BuildContext ctx) async {
    final st = AppState.instance;
    final cur = st.feedSort.value;
    final v = await showDialog<String>(
      context: ctx,
      builder: (c) => _pickDialog<String>(
        title: Lc.current.feedSort,
        current: cur,
        options: [('updated', Lc.current.sortUpdated), ('created', Lc.current.sortCreated)],
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
        options: [(0, Lc.current.timeline), (1, Lc.current.forums), (2, Lc.current.notice), (3, Lc.current.me)],
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
          subtitle: Text(_useBeta ? Lc.current.betaChannelHint : Lc.current.stableChannelHint),
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
      await _tell(Lc.current.checkUpdate, Lc.current.upToDate('${_pkg?.version ?? ''}'));
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

    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(r.channel == 'beta' ? Lc.current.betaVersion('${r.version}') : Lc.current.newVersion('${r.version}')),
        content: ConstrainedBox(
          // 小屏（手表）上不加这层，正文会把按钮顶出可视区。
          constraints: BoxConstraints(
            maxHeight:
                (MediaQuery.of(context).size.height * 0.5).clamp(96.0, 340.0),
          ),
          child: SingleChildScrollView(
            child: Text(
              r.notes.isEmpty
                  ? Lc.current.installOverwrite('${r.sizeText}')
                  : Lc.current.releaseNotes('${r.notes}', '${r.sizeText}'),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(Lc.current.later),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(Lc.current.downloadAndInstall),
          ),
        ],
      ),
    );
    if (go == true && mounted) await _install(r);
  }

  Future<void> _tell(String title, String body) {
    return showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(Lc.current.ok)),
        ],
      ),
    );
  }

  Future<void> _install(AppRelease r) async {
    // 用 ValueNotifier 推进度：弹窗里的 StatefulBuilder 拿不到外面的 setState。
    final prog = ValueNotifier<double>(0);
    final nav = Navigator.of(context);
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (c) => AlertDialog(
          title: Text(Lc.current.downloading),
          content: ValueListenableBuilder<double>(
            valueListenable: prog,
            builder: (_, v, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: v <= 0 ? null : v),
                const SizedBox(height: 14),
                Text('${(v * 100).toStringAsFixed(0)}%'),
              ],
            ),
          ),
        ),
      ),
    );
    try {
      final file = await downloadApk(r, (v) => prog.value = v);
      if (mounted) nav.pop();
      await openLocalFile(file.path);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(
        content: Text(
          isDesktop ? Lc.current.handedToSystem : Lc.current.handedToInstaller,
        ),
      ));
    } catch (e) {
      if (mounted) nav.pop();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(Lc.current.downloadFailedWith('${e}'))));
    }
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              Lc.current.endpointHint,
              style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
            ),
          ),
        ],
      ],
    );
  }

  void _copy(BuildContext context, String s) {
    Clipboard.setData(ClipboardData(text: s));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(Lc.current.addressCopied)),
    );
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(before > 0 ? Lc.current.clearedAmount('${AppCache.human(before)}') : Lc.current.cleared)),
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
