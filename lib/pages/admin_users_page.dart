import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../store.dart';

/// 管理员：账号管理。
///
/// 只干一件事——把某个人的密码重置成随机临时密码。
/// 给那些没绑邮箱、旧设备也没留登录凭证的人用，是最后一道口子。
class AdminUsersPage extends StatefulWidget {
  const AdminUsersPage({super.key});

  @override
  State<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends State<AdminUsersPage> {
  final _q = TextEditingController();
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final items = await AppState.instance.adminUsers(_q.text.trim());
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _err = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _reset(Map<String, dynamic> u) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('重置密码'),
        content: Text(
          '把「${u['nickname'] ?? u['name']}」的密码换成随机的一串？\n\n'
          '原密码会立刻失效。新密码只显示一次，记得发给本人。',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('算了')),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('重置'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      final r = await AppState.instance.adminResetPw(u['id'] as int);
      if (!mounted) return;
      final pw = (r['password'] ?? '') as String;
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('新密码'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('给「${r['nickname'] ?? r['name']}」的新密码：'),
              const SizedBox(height: 12),
              SelectableText(
                pw,
                style: const TextStyle(
                  fontSize: 20,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '关掉就看不到了。让本人登录后马上改成自己记得的。',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: pw));
                if (c.mounted) Navigator.pop(c);
              },
              child: const Text('复制并关闭'),
            ),
          ],
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('账号管理'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: TextField(
              controller: _q,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _load(),
              decoration: InputDecoration(
                hintText: '搜用户名',
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: _load,
                ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _err != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_err!, style: TextStyle(color: cs.error)),
                  const SizedBox(height: 12),
                  OutlinedButton(onPressed: _load, child: const Text('重试')),
                ],
              ),
            )
          : ListView.separated(
              itemCount: _items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final u = _items[i];
                final mail = (u['email'] ?? '') as String;
                return ListTile(
                  title: Row(
                    children: [
                      Flexible(
                        child: Text(
                          (u['nickname'] ?? u['name']) as String,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (u['is_admin'] == true) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.shield_outlined, size: 14, color: cs.primary),
                      ],
                    ],
                  ),
                  subtitle: Text(
                    mail.isEmpty ? '没绑邮箱' : mail,
                    style: mail.isEmpty
                        ? TextStyle(color: cs.error, fontSize: 12)
                        : const TextStyle(fontSize: 12),
                  ),
                  trailing: TextButton(
                    onPressed: () => _reset(u),
                    child: const Text('重置密码'),
                  ),
                );
              },
            ),
    );
  }
}
