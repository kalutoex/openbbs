import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../api.dart';
import '../site_config.dart';
import '../store.dart';
import '../widgets/name_tag.dart';
import 'login_page.dart';
import 'follow_page.dart';
import 'settings_page.dart';
import 'thread_list_page.dart';
import 'user_page.dart';

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
          tooltip: '菜单',
        ),
        titleSpacing: 0,
        title: const Text('我的', style: TextStyle(fontWeight: FontWeight.w700)),
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
                                const Text(
                                  '还没登录',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '登录后可以发帖、回复、关注團',
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
                            child: const Text('登录'),
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
                ListTile(
                  leading: const Icon(Icons.people_outline),
                  title: const Text('关注'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => const FollowPage())),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.star_border),
                  title: const Text('我的收藏'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ThreadListPage(
                        title: '我的收藏',
                        path: '/favorites',
                        emptyText: '还没收藏过線',
                      ),
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.history),
                  title: const Text('浏览历史'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ThreadListPage(
                        title: '浏览历史',
                        path: '/history',
                        emptyText: '还没有浏览记录',
                      ),
                    ),
                  ),
                ),
              ],
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('设置'),
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
