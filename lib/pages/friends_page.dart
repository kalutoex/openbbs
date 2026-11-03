import 'package:flutter/material.dart';

import '../api.dart';
import '../store.dart';
import '../widgets/avatar.dart';
import 'user_page.dart';

import '../l10n/error_text.dart';
/// 致谢：把成员挂出来。管理员可以直接增删。
class FriendsPage extends StatefulWidget {
  const FriendsPage({super.key});

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> {
  List<dynamic>? _items;
  String? _err;
  bool _canManage = false;

  /// 以服务端为准：请求带了有效 token 且是管理员才为真。
  bool get _isAdmin =>
      _canManage || AppState.instance.user?['is_admin'] == true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await Api.get('/friends');
      if (!mounted) return;
      setState(() {
        _items = (d['items'] as List?) ?? [];
        _canManage = d['can_manage'] == true;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _err = errorText(context, e));
    } catch (_) {
      if (mounted) setState(() => _err = '连不上服务器');
    }
  }

  Future<void> _add() async {
    final ctl = TextEditingController();
    String? err;
    var busy = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('加人'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctl,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '用户名 / @标识 / 昵称',
                  errorText: null,
                ),
                onSubmitted: (_) {},
              ),
              if (err != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    err!,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Theme.of(ctx).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      final q = ctl.text.trim();
                      if (q.isEmpty) {
                        setD(() => err = '写个名字');
                        return;
                      }
                      setD(() {
                        busy = true;
                        err = null;
                      });
                      try {
                        await Api.post('/friends', {'q': q});
                        if (ctx.mounted) Navigator.of(ctx).pop(true);
                      } on ApiException catch (e) {
                        setD(() {
                          busy = false;
                          err = errorText(context, e);
                        });
                      } catch (_) {
                        setD(() {
                          busy = false;
                          err = '连不上服务器';
                        });
                      }
                    },
              child: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('添加'),
            ),
          ],
        ),
      ),
    );
    ctl.dispose();
    if (ok == true) _load();
  }

  Future<void> _remove(Map u) async {
    final nick = (u['nickname'] ?? u['name'] ?? '') as String;
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('把 $nick 拿下来？'),
        content: const Text('只是从这页去掉，账号还在。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('算了'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('拿下来'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    try {
      await Api.delete('/friends/${u['id']}');
      _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorText(context, e))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('致谢'),
        actions: [
          if (_isAdmin)
            IconButton(
              tooltip: '加人',
              icon: const Icon(Icons.person_add_alt_1),
              onPressed: _add,
            ),
        ],
      ),
      body: Builder(
        builder: (context) {
          if (_err != null) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_err!, style: TextStyle(color: cs.onSurfaceVariant)),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () {
                      setState(() => _err = null);
                      _load();
                    },
                    child: const Text('再试一次'),
                  ),
                ],
              ),
            );
          }
          final items = _items;
          if (items == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (items.isEmpty) {
            return Center(
              child: Text('还没有人', style: TextStyle(color: cs.onSurfaceVariant)),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: items.length + (_isAdmin ? 0 : 1),
            itemBuilder: (context, i) {
              if (i >= items.length) {
                final me = AppState.instance.user;
                final who = me == null
                    ? '未登录'
                    : ((me['nickname'] ?? me['name'] ?? '') as String);
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                  child: Text(
                    '这份名单只有管理员能改（当前登录：$who）。',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                );
              }
              final u = items[i] as Map;
              final nick = (u['nickname'] ?? u['name'] ?? '') as String;
              final handle = (u['handle'] ?? '') as String;
              final sig = (u['signature'] ?? '') as String;
              final sub =
                  sig.isNotEmpty ? sig : (handle.isNotEmpty ? '@$handle' : '');
              return ListTile(
                leading: CircleAvatarImg(
                  url: (u['avatar'] ?? '') as String,
                  name: nick,
                  radius: 20,
                ),
                title: Text(
                  nick,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: sub.isEmpty
                    ? null
                    : Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                trailing: _isAdmin
                    ? IconButton(
                        tooltip: '拿下来',
                        icon: Icon(
                          Icons.remove_circle_outline,
                          size: 20,
                          color: cs.onSurfaceVariant,
                        ),
                        onPressed: () => _remove(u),
                      )
                    : null,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        UserPage(name: (u['name'] ?? '') as String),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
