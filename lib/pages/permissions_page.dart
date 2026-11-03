import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../permissions.dart';

/// 权限页：通知、相册各自显示状态，点一下就能申请或去系统设置。
/// 联网权限装完就有，运行时没有弹窗，这里只做说明。
class PermissionsPage extends StatefulWidget {
  const PermissionsPage({super.key});

  @override
  State<PermissionsPage> createState() => _PermissionsPageState();
}

class _PermissionsPageState extends State<PermissionsPage> {
  Map<Permission, PermissionStatus> _st = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final m = await AppPerms.statuses();
    if (!mounted) return;
    setState(() {
      _st = m;
      _loading = false;
    });
  }

  Future<void> _ask(Permission p) async {
    final s = await AppPerms.ask(p);
    if (!mounted) return;
    setState(() => _st = {..._st, p: s});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('权限')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
                  child: Text(
                    '联网权限安装时已经给了，这里只剩通知和相册需要你点头。',
                    style: TextStyle(fontSize: 13, color: cs.outline),
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(Icons.wifi),
                  title: const Text('联网'),
                  subtitle: const Text('安装时自动授予，不用管'),
                  trailing: Text(
                    '已允许',
                    style: TextStyle(fontSize: 13, color: cs.outline),
                  ),
                ),
                const Divider(height: 24),
                for (final p in AppPerms.list)
                  ListTile(
                    leading: Icon(
                      p == Permission.notification
                          ? Icons.notifications_none
                          : Icons.photo_library_outlined,
                    ),
                    title: Text(AppPerms.label(p)),
                    subtitle: Text(AppPerms.subtitle(p)),
                    trailing: Text(
                      AppPerms.text(_st[p] ?? PermissionStatus.denied),
                      style: TextStyle(fontSize: 12, color: cs.outline),
                    ),
                    onTap: () => _ask(p),
                  ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    '不想开的可以一直关着，只是发图时得手动去系统里选。',
                    style: TextStyle(fontSize: 12, color: cs.outline),
                  ),
                ),
              ],
            ),
    );
  }
}
