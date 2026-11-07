import 'package:flutter/material.dart';

import '../user_hue.dart';
import '../api.dart';
import '../store.dart';
import '../utils.dart';
import '../widgets/app_card.dart';
import '../widgets/app_sheet.dart';
import '../widgets/empty_view.dart';
import '../widgets/page_width.dart';
import '../widgets/avatar.dart';
import '../l10n/error_text.dart';
import '../l10n/l10n.dart';
import 'chat_page.dart';
import 'login_page.dart';
import 'notice_page.dart';
import '../widgets/toast.dart';

/// 消息：站内消息和私信会话混在一起按时间排，置顶的会话永远在最上面。
class MessagesPage extends StatefulWidget {
  final VoidCallback onMenu;

  const MessagesPage({super.key, required this.onMenu});

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

/// 一行。站内消息和私信会话长得不一样，但排序、长按菜单共用一套。
class _Row {
  final bool notice;
  final int threadId;
  final Map<String, dynamic>? peer;
  final String text;
  final int at;
  final int unread;
  final bool pinned;
  final bool muted;

  _Row({
    required this.notice,
    required this.threadId,
    required this.peer,
    required this.text,
    required this.at,
    required this.unread,
    required this.pinned,
    required this.muted,
  });

  String get title => notice
      ? Lc.current.siteMessages
      : (peer?['nickname'] ?? peer?['name'] ?? '') as String;
}

class _MessagesPageState extends State<MessagesPage> {
  final List<_Row> _rows = [];
  bool _loading = true;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!AppState.instance.loggedIn) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _rows.clear();
      });
      return;
    }
    try {
      // 两个接口一起发，别串着等。
      final r = await Future.wait([Api.get('/dm'), Api.get('/notifications')]);
      if (!mounted) return;
      final dm = r[0] as Map<String, dynamic>;
      final nt = r[1] as Map<String, dynamic>;
      final rows = <_Row>[];

      for (final it in (dm['items'] as List).cast<Map<String, dynamic>>()) {
        rows.add(
          _Row(
            notice: false,
            threadId: (it['thread_id'] ?? 0) as int,
            peer: (it['peer'] as Map).cast<String, dynamic>(),
            text: (it['last'] ?? '') as String,
            at: (it['last_at'] ?? 0) as int,
            unread: (it['unread'] ?? 0) as int,
            pinned: it['pinned'] == true,
            muted: it['muted'] == true,
          ),
        );
      }

      final noticeItems = (nt['items'] as List).cast<Map<String, dynamic>>();
      if (noticeItems.isNotEmpty) {
        final n = noticeItems.first;
        final actor = (n['actor'] ?? '') as String;
        final kind = (n['kind'] ?? '') as String;
        final at = (n['created_at'] ?? 0) as int;
        rows.add(
          _Row(
            notice: true,
            threadId: 0,
            peer: null,
            text: '$actor ${noticeActionText(kind)}',
            at: at,
            unread: (nt['unread'] ?? 0) as int,
            pinned: false,
            muted: false,
          ),
        );
      }

      // 置顶的排前面，其余按时间。站内消息也按时间参与，不单独钉在顶部。
      rows.sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        return b.at.compareTo(a.at);
      });

      setState(() {
        _rows
          ..clear()
          ..addAll(rows);
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

  Future<void> _open(_Row row) async {
    if (row.notice) {
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const NoticePage()));
    } else {
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => ChatPage(peer: row.peer!)));
    }
    if (!mounted) return;
    _load();
  }

  /// 长按菜单。站内消息只有「标为已读」，会话还有置顶、免打扰、删除。
  Future<void> _menu(_Row row) async {
    final l = Lc.current;
    final cs = Theme.of(context).colorScheme;
    final actions = <Widget>[];

    Future<void> run(Future Function() fn) async {
      Navigator.of(context).pop();
      try {
        await fn();
      } on ApiException catch (e) {
        if (!mounted) return;
        toast(context, errorText(context, e));
        return;
      }
      if (!mounted) return;
      await _load();
    }

    if (row.notice) {
      if (row.unread > 0) {
        actions.add(
          ListTile(
            leading: const Icon(Icons.mark_email_read_outlined),
            title: Text(l.markRead),
            onTap: () => run(() => Api.post('/notifications/read', {})),
          ),
        );
      }
    } else {
      actions.addAll([
        ListTile(
          leading: Icon(
            row.pinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
          ),
          title: Text(row.pinned ? l.unpinChat : l.pinChat),
          onTap: () => run(
            () =>
                Api.post('/dm/${row.threadId}/state', {'pinned': !row.pinned}),
          ),
        ),
        ListTile(
          leading: Icon(
            row.muted
                ? Icons.notifications_active_outlined
                : Icons.notifications_off_outlined,
          ),
          title: Text(row.muted ? l.unmuteChat : l.muteChat),
          onTap: () => run(
            () => Api.post('/dm/${row.threadId}/state', {'muted': !row.muted}),
          ),
        ),
        if (row.unread > 0)
          ListTile(
            leading: const Icon(Icons.mark_email_read_outlined),
            title: Text(l.markRead),
            onTap: () => run(() => Api.post('/dm/${row.peer!['id']}/read', {})),
          ),
        ListTile(
          leading: Icon(Icons.delete_outline_rounded, color: cs.error),
          title: Text(l.deleteChat, style: TextStyle(color: cs.error)),
          onTap: () => run(
            () => Api.post('/dm/${row.threadId}/state', {'hidden': true}),
          ),
        ),
      ]);
    }

    if (actions.isEmpty) return;
    await showAppSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: actions),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: widget.onMenu,
          icon: const Icon(Icons.menu_rounded),
          tooltip: Lc.current.menu,
        ),
        titleSpacing: 0,
        title: Text(
          Lc.current.messagesTab,
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      body: PageWidth(
        child: RefreshIndicator(onRefresh: _load, child: _body(context)),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (!AppState.instance.loggedIn) {
      return EmptyView(
        icon: Icons.lock_outline_rounded,
        title: Lc.current.noticeLoginNeeded,
        hint: Lc.current.loginBenefits,
        action: FilledButton(
          onPressed: () =>
              Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const LoginPage())),
          child: Text(Lc.current.login),
        ),
      ).scrollable();
    }
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_err != null) {
      return EmptyView(
        icon: Icons.cloud_off_rounded,
        title: _err!,
        error: true,
        action: FilledButton.tonal(
          onPressed: () {
            setState(() => _loading = true);
            _load();
          },
          child: Text(Lc.current.retry),
        ),
      ).scrollable();
    }
    if (_rows.isEmpty) {
      return EmptyView(
        icon: Icons.forum_outlined,
        title: Lc.current.dmEmpty,
        hint: Lc.current.dmEmptyHint,
      ).scrollable();
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
      itemCount: _rows.length,
      itemBuilder: (context, i) {
        final row = _rows[i];
        // 会话卡跟着对方走色；站内消息没有「对方」，留着默认底。
        final dark = Theme.of(context).brightness == Brightness.dark;
        return AppCard(
          margin: const EdgeInsets.only(bottom: 8),
          // 会话卡一直跟着对方走色，不进彩蛋里的那个开关。
          color: row.notice || row.peer == null
              ? null
              : hueCardBg(hueOfUser(row.peer), dark),
          child: _tile(context, row),
        );
      },
    );
  }

  Widget _tile(BuildContext context, _Row row) {
    final cs = Theme.of(context).colorScheme;
    final name = row.title;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: row.notice
          ? CircleAvatar(
              radius: 22,
              backgroundColor: cs.secondaryContainer,
              child: Icon(
                Icons.notifications_rounded,
                color: cs.onSecondaryContainer,
              ),
            )
          : CircleAvatarImg(
              url: (row.peer!['avatar'] ?? '') as String,
              name: name,
              radius: 22,
              hue: hueOfUser(row.peer),
            ),
      title: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (row.muted) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.volume_off_rounded, size: 14, color: cs.outline),
                ],
              ],
            ),
          ),
          Text(
            row.at > 0 ? timeAgo(row.at) : '',
            style: TextStyle(fontSize: 11.5, color: cs.outline),
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          children: [
            Expanded(
              child: Text(
                row.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
              ),
            ),
            if (row.unread > 0) ...[
              const SizedBox(width: 8),
              // 免打扰的会话数字压灰，不抢眼。
              Badge(
                backgroundColor: row.muted ? cs.outline : null,
                label: Text(row.unread > 99 ? '99+' : '${row.unread}'),
              ),
            ],
          ],
        ),
      ),
      onTap: () => _open(row),
      onLongPress: () => _menu(row),
    );
  }
}
