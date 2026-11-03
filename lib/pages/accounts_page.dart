import 'package:flutter/material.dart';

import '../accounts.dart';
import '../store.dart';
import '../widgets/avatar.dart';
import 'login_page.dart';

/// 本机登录过的账号列表。点一下就换，不用重新输密码。
class AccountsPage extends StatelessWidget {
  const AccountsPage({super.key});

  Future<void> _switch(BuildContext context, Account a) async {
    final st = AppState.instance;
    if (a.token == st.activeAccount?.token) {
      Navigator.of(context).pop();
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final ok = await st.switchAccount(a);
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(ok ? '已切换到 ${a.nickname}' : '${a.nickname} 的登录已失效，已移除'),
      ),
    );
    if (ok) nav.pop();
  }

  Future<void> _remove(BuildContext context, Account a) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('移除账号'),
        content: Text('从本机移除 ${a.nickname}？只是退出这台设备，账号和帖子都还在服务器上。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('算了'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await AppState.instance.removeAccount(a);
  }

  Future<void> _add(BuildContext context) async {
    final st = AppState.instance;
    final before = st.accounts.length;
    final ok = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => const LoginPage()));
    if (!context.mounted) return;
    if (ok == true && st.accounts.length > before) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已添加 ${st.activeAccount?.nickname ?? '账号'}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final st = AppState.instance;

    return Scaffold(
      appBar: AppBar(title: const Text('账号')),
      body: ListenableBuilder(
        listenable: st,
        builder: (context, _) {
          final list = st.accounts;
          final active = st.activeAccount;
          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 32, 16, 16),
                  child: Text('还没有账号'),
                ),
              for (final a in list)
                ListTile(
                  leading: CircleAvatarImg(
                    url: a.avatar,
                    name: a.nickname,
                    radius: 22,
                  ),
                  title: Text(a.nickname),
                  subtitle: Text(
                    [
                      if (a.uid.isNotEmpty) 'UID ${a.uid}',
                      if (a.handle.isNotEmpty) '@${a.handle}',
                    ].join(' · '),
                  ),
                  trailing: a.token == active?.token
                      ? Icon(Icons.check_circle, color: cs.primary)
                      : IconButton(
                          tooltip: '移除',
                          icon: const Icon(Icons.close),
                          onPressed: () => _remove(context, a),
                        ),
                  onTap: () => _switch(context, a),
                  onLongPress: () => _remove(context, a),
                ),
              const Divider(height: 24),
              ListTile(
                leading: const Icon(Icons.person_add_alt_1_outlined),
                title: const Text('添加账号'),
                subtitle: const Text('登录另一个账号，之后可以随时切回来'),
                onTap: () => _add(context),
              ),
              ListTile(
                leading: const Icon(Icons.vpn_key_outlined),
                title: const Text('粘贴登录凭证'),
                subtitle: const Text('把别的设备上的账号加进这台机器'),
                onTap: () => _add(context),
              ),
            ],
          );
        },
      ),
    );
  }
}
