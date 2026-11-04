import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../api.dart';
import '../cloud.dart' hide CloudPage;
import '../site_config.dart';
import '../store.dart';
import '../utils.dart';
import '../widgets/name_tag.dart';
import 'cloud_page.dart';
import 'login_page.dart';
import 'follow_page.dart';
import 'settings_page.dart';
import 'thread_list_page.dart';
import 'user_page.dart';

import '../l10n/l10n.dart';
class MeTab extends StatelessWidget {
  final VoidCallback onMenu;

  const MeTab({super.key, required this.onMenu});

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
        title: Text(Lc.current.me, style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: ListenableBuilder(
        listenable: AppState.instance,
        builder: (context, _) {
          final st = AppState.instance;
          final u = st.user;
          final cs = Theme.of(context).colorScheme;
          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
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
                                const SizedBox(height: 4),
                                Text(
                                  Lc.current.loginBenefits,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: cs.outline,
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
                            builder: (_) => UserPage(name: u['name'] as String),
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
                const Padding(
                  padding: EdgeInsets.fromLTRB(12, 10, 12, 4),
                  child: _CloudCard(),
                ),
                ListTile(
                  leading: const Icon(Icons.people_outline),
                  title: Text(Lc.current.follow),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => const FollowPage())),
                ),
                const Divider(height: 1),
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
                const Divider(height: 1),
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
              ],
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: Text(Lc.current.settings),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const SettingsPage())),
              ),
              const Divider(height: 1),
              const SizedBox(height: 30),
              Center(child: _VersionFooter(color: cs.outline)),
            ],
          );
        },
      ),
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
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CloudPage()));
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

    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _open,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
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
        ),
      ),
    );
  }
}
