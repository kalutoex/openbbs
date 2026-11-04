import 'package:flutter/material.dart';

import '../api.dart';
import '../store.dart';
import '../widgets/avatar.dart';
import '../l10n/error_text.dart';
import '../l10n/l10n.dart';
import 'chat_page.dart';
import 'user_page.dart';

/// 私信列表。一行一个会话，右边是最后一条和未读数。
class InboxPage extends StatefulWidget {
  const InboxPage({super.key});

  @override
  State<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends State<InboxPage> {
  final List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await Api.get('/dm');
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll((d['items'] as List).cast<Map<String, dynamic>>());
        _loading = false;
        _err = null;
      });
      AppState.instance.refreshDmUnread();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _err = errorText(context, e);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _err = '$e';
      });
    }
  }

  Future<void> _open(Map<String, dynamic> it) async {
    final peer = it['peer'] as Map<String, dynamic>;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ChatPage(peer: peer)),
    );
    if (!mounted) return;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(Lc.current.dmTitle)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _body(context),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_err != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(_err!, textAlign: TextAlign.center),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: () {
                setState(() => _loading = true);
                _load();
              },
              child: Text(Lc.current.retry),
            ),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      // 空态也要能下拉刷新，所以套一层可滚的
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          Icon(Icons.forum_outlined, size: 48, color: cs.outline),
          const SizedBox(height: 12),
          Center(
            child: Text(Lc.current.dmEmpty,
                style: TextStyle(color: cs.onSurfaceVariant)),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(Lc.current.dmEmptyHint,
                style: TextStyle(fontSize: 12, color: cs.outline)),
          ),
        ],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _items.length,
      separatorBuilder: (_, i) => const Divider(height: 1, indent: 72),
      itemBuilder: (context, i) {
        final it = _items[i];
        final peer = it['peer'] as Map<String, dynamic>;
        final name = (peer['nickname'] ?? peer['name'] ?? '') as String;
        final unread = (it['unread'] ?? 0) as int;
        final last = (it['last'] ?? '') as String;
        return ListTile(
          leading: CircleAvatarImg(
            url: (peer['avatar'] ?? '') as String,
            name: name,
            radius: 22,
          ),
          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            last,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
          trailing: unread > 0
              ? Badge(
                  label: Text(unread > 99 ? '99+' : '$unread'),
                  child: const SizedBox(width: 20, height: 20),
                )
              : null,
          onTap: () => _open(it),
          onLongPress: () {
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => UserPage(name: (peer['name'] ?? '') as String),
            ));
          },
        );
      },
    );
  }
}
