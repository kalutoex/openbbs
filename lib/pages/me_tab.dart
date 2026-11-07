import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../api.dart';
import '../cloud.dart' hide CloudPage;
import '../site_config.dart';
import '../store.dart';
import '../trash.dart';
import '../utils.dart';
import '../widgets/app_card.dart';
import '../widgets/page_width.dart';
import '../widgets/name_tag.dart';
import 'admin_trash_page.dart';
import 'cloud_page.dart';
import 'downloads_page.dart';
import 'login_page.dart';
import 'follow_page.dart';
import 'settings_page.dart';
import 'thread_list_page.dart';
import 'trash_page.dart';
import 'user_page.dart';

import '../l10n/l10n.dart';

class MeTab extends StatelessWidget {
  final VoidCallback onMenu;

  const MeTab({super.key, required this.onMenu});

  /// 卡片内部的分隔线：左边空出图标宽度，别从卡片边缘拉通。
  static Widget _hairLine(ColorScheme cs) => Divider(
    height: 1,
    indent: 56,
    color: cs.outlineVariant.withValues(alpha: 0.35),
  );

  static String _avatarOf(Map<String, dynamic> u) =>
      ((u['avatar'] ?? '') as String).trim();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: onMenu,
          icon: const Icon(Icons.menu),
          tooltip: Lc.current.menu,
        ),
        titleSpacing: 0,
        title: Text(
          Lc.current.me,
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: PageWidth(
        child: ListenableBuilder(
          listenable: AppState.instance,
          builder: (context, _) {
            final st = AppState.instance;
            final u = st.user;
            final cs = Theme.of(context).colorScheme;
            return ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 26),
              children: [
                AppCard(
                  padding: const EdgeInsets.all(16),
                  child: u == null
                      ? Row(
                          children: [
                            CircleAvatar(
                              radius: 30,
                              backgroundColor: cs.surfaceContainerHighest,
                              child: Icon(Icons.person, color: cs.outline),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    Lc.current.notLoggedIn,
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            FilledButton(
                              onPressed: () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const LoginPage(),
                                  ),
                                );
                              },
                              child: Text(Lc.current.login),
                            ),
                          ],
                        )
                      : InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  UserPage(name: u['name'] as String),
                            ),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 30,
                                backgroundColor: cs.primaryContainer,
                                backgroundImage: _avatarOf(u).isEmpty
                                    ? null
                                    : NetworkImage(Api.img(_avatarOf(u))),
                                child: _avatarOf(u).isNotEmpty
                                    ? null
                                    : Text(
                                        ((u['nickname'] ?? u['name']) as String)
                                            .substring(0, 1),
                                        style: TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w700,
                                          color: cs.onPrimaryContainer,
                                        ),
                                      ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: NameTag(
                                            name:
                                                (u['nickname'] ?? u['name'])
                                                    as String,
                                            handle: '${u['handle'] ?? ''}',
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 5,
                                            vertical: 1,
                                          ),
                                          decoration: BoxDecoration(
                                            color: cs.tertiaryContainer,
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: Text(
                                            'Lv${u['level'] ?? 1}',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              color: cs.onTertiaryContainer,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      'UID ${u['uid'] ?? u['id']}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: cs.outline,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
                if (u != null) ...[
                  const SizedBox(height: 10),
                  const _CloudCard(),
                  const SizedBox(height: 10),
                  AppCard(
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.people_outline),
                          title: Text(Lc.current.follow),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const FollowPage(),
                            ),
                          ),
                        ),
                        _hairLine(cs),
                        ListTile(
                          leading: const Icon(Icons.star_border),
                          title: Text(Lc.current.myFavorites),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ThreadListPage(
                                title: Lc.current.myFavorites,
                                path: '/favorites',
                                emptyText: Lc.current.noFavoritesYet,
                              ),
                            ),
                          ),
                        ),
                        _hairLine(cs),
                        ListTile(
                          leading: const Icon(Icons.history),
                          title: Text(Lc.current.browseHistory),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ThreadListPage(
                                title: Lc.current.browseHistory,
                                path: '/history',
                                emptyText: Lc.current.noHistoryYet,
                              ),
                            ),
                          ),
                        ),
                        _hairLine(cs),
                        ListTile(
                          leading: const Icon(Icons.download_done_outlined),
                          title: Text(Lc.current.downloadsPage),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const DownloadsPage(),
                            ),
                          ),
                        ),
                        _hairLine(cs),
                        _TrashEntry(admin: (u['is_admin'] ?? false) == true),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ] else
                  const SizedBox(height: 10),
                AppCard(
                  child: ListTile(
                    leading: const Icon(Icons.settings_outlined),
                    title: Text(Lc.current.settings),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsPage()),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Center(child: _VersionFooter(color: cs.outline)),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 回收站入口。数字放这儿，别让人点进去才知道有没有东西。
class _TrashEntry extends StatefulWidget {
  const _TrashEntry({required this.admin});

  final bool admin;

  @override
  State<_TrashEntry> createState() => _TrashEntryState();
}

class _TrashEntryState extends State<_TrashEntry> {
  TrashSummary? _sum;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await TrashApi.summary();
      if (!mounted) return;
      setState(() => _sum = s);
    } catch (_) {
      // 拿不到就不显示数字，不打扰
    }
  }

  Future<void> _open() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const TrashPage()),
    );
    if (mounted) _load();
  }

  Future<void> _openAdmin() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AdminTrashPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final n = _sum?.total ?? 0;
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.delete_outline),
          title: Text(Lc.current.recycleBin),
          subtitle: n > 0
              ? Text(
                  '${Lc.current.trashThreadsTab} ${_sum!.threads} · '
                  '${Lc.current.trashFilesTab} ${_sum!.files}',
                  style: const TextStyle(fontSize: 12),
                )
              : null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (n > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: cs.errorContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$n',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: cs.onErrorContainer,
                    ),
                  ),
                ),
              const Icon(Icons.chevron_right),
            ],
          ),
          onTap: _open,
        ),
        if (widget.admin)
          ListTile(
            leading: const Icon(Icons.admin_panel_settings_outlined),
            title: Text(Lc.current.adminTrash),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openAdmin,
          ),
      ],
    );
  }
}

/// 底部版本号：直接读安装包，跟着构建号走，不用手改。
class _VersionFooter extends StatelessWidget {
  final Color color;

  const _VersionFooter({required this.color});

  static final Future<PackageInfo> _pkg = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: _pkg,
      builder: (context, snap) {
        final p = snap.data;
        final text = p == null
            ? SiteConfig.brand
            : '${SiteConfig.brand} · ${p.version} (${p.buildNumber})';
        return Text(text, style: TextStyle(fontSize: 11, color: color));
      },
    );
  }
}

/// 云盘容量卡：进度条 + 「已用 / 总量」。
///
/// 自己拉一次 /cloud/usage，不拖累整页；拿不到就显示 -- / --，不弹错误。
class _CloudCard extends StatefulWidget {
  const _CloudCard();

  @override
  State<_CloudCard> createState() => _CloudCardState();
}

class _CloudCardState extends State<_CloudCard> {
  CloudUsage? _usage;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final u = await CloudApi.usage();
      if (!mounted) return;
      setState(() {
        _usage = u;
        _failed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  Future<void> _open() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const CloudPage()));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final u = _usage;
    final ok = u != null && !_failed;
    final usedText = ok ? bytesShort(u.used) : '--';
    final totalText = !ok
        ? '--'
        : u.unlimited
        ? '∞'
        : bytesShort(u.quota!);

    return AppCard(
      onTap: _open,
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.cloud_outlined, size: 18, color: cs.primary),
              const SizedBox(width: 6),
              Text(
                Lc.current.cloudDisk,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '$usedText / $totalText',
                style: TextStyle(fontSize: 12, color: cs.outline),
              ),
              const SizedBox(width: 2),
              Icon(Icons.chevron_right, size: 16, color: cs.outline),
            ],
          ),
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: u?.ratio ?? 0,
              minHeight: 5,
              backgroundColor: cs.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}
