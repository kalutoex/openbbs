import 'package:flutter/material.dart';

import '../accounts.dart';
import '../widgets/page_width.dart';
import '../store.dart';
import '../widgets/app_card.dart';
import '../widgets/avatar.dart';
import 'login_page.dart';

import '../l10n/l10n.dart';
import '../widgets/toast.dart';

/// 本机登录过的账号列表。点一下就换，不用重新输密码。
class AccountsPage extends StatelessWidget {
  const AccountsPage({super.key});

  Future<void> _switch(BuildContext context, Account a) async {
    final st = AppState.instance;
    if (a.token == st.activeAccount?.token) {
      Navigator.of(context).pop();
      return;
    }
    final nav = Navigator.of(context);
    final ok = await st.switchAccount(a);
    if (!context.mounted) return;
    toast(
      context,
      ok
          ? Lc.current.switchedTo('${a.nickname}')
          : Lc.current.accountExpiredRemoved('${a.nickname}'),
    );
    if (ok) nav.pop();
  }

  Future<void> _remove(BuildContext context, Account a) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(Lc.current.removeAccount),
        content: Text(Lc.current.removeAccountConfirm('${a.nickname}')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(Lc.current.forgetIt),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(Lc.current.remove),
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
      toast(
        context,
        Lc.current.accountAdded(
          '${st.activeAccount?.nickname ?? Lc.current.accounts}',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final st = AppState.instance;

    return Scaffold(
      appBar: AppBar(title: Text(Lc.current.accounts)),
      body: PageWidth(
        child: ListenableBuilder(
          listenable: st,
          builder: (context, _) {
            final list = st.accounts;
            final active = st.activeAccount;
            return ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
              children: [
                if (list.isEmpty)
                  AppCard(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      leading: const Icon(Icons.people_outline),
                      title: Text(Lc.current.noAccounts),
                    ),
                  ),
                AppCard(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Column(
                    children: [
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
                                  tooltip: Lc.current.remove,
                                  icon: const Icon(Icons.close),
                                  onPressed: () => _remove(context, a),
                                ),
                          onTap: () => _switch(context, a),
                          onLongPress: () => _remove(context, a),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                AppCard(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: ListTile(
                    leading: const Icon(Icons.person_add_alt_1_outlined),
                    title: Text(Lc.current.addAccount),
                    subtitle: Text(Lc.current.addAccountHint),
                    onTap: () => _add(context),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
