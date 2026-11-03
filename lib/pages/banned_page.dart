import 'package:flutter/material.dart';

import '../store.dart';

import '../l10n/l10n.dart';
/// 账号被封。整页替换，不留别的入口。
///
/// 服务端封号一律 403 + 固定文案，接口层认出来就置 `AppState.banned`，
/// 这里只负责把话说清楚并给一条退出的路。
class BannedPage extends StatelessWidget {
  const BannedPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.block_rounded, size: 64, color: cs.error),
                const SizedBox(height: 20),
                Text(
                  Lc.current.bannedTitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Text(
                  Lc.current.bannedBody,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 28),
                FilledButton(
                  // 退出就清掉封禁标记，回到没登录的首页。
                  onPressed: () => AppState.instance.logout(),
                  child: Text(Lc.current.logout),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
