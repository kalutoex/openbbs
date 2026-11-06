import '../widgets/app_card.dart';
import '../widgets/page_width.dart';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../permissions.dart';

import '../l10n/l10n.dart';

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
      appBar: AppBar(title: Text(Lc.current.permissions)),
      body: PageWidth(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                    child: Text(
                      Lc.current.permIntro,
                      style: TextStyle(fontSize: 13, color: cs.outline),
                    ),
                  ),
                  AppCard(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.wifi),
                          title: Text(Lc.current.network),
                          subtitle: Text(Lc.current.networkGranted),
                          trailing: Text(
                            Lc.current.allowed,
                            style: TextStyle(fontSize: 13, color: cs.outline),
                          ),
                        ),
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
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
