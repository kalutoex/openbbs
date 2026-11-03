import 'package:flutter/material.dart';

import '../api.dart';
import '../store.dart';
import '../utils.dart';
import 'thread_page.dart';

/// 通知：回复、楼中楼、赞。
class NoticeTab extends StatefulWidget {
  final VoidCallback onMenu;

  const NoticeTab({super.key, required this.onMenu});

  @override
  State<NoticeTab> createState() => _NoticeTabState();
}

class _NoticeTabState extends State<NoticeTab> {
  final List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!AppState.instance.loggedIn) {
      if (mounted) {
        setState(() {
          _loading = false;
          _items.clear();
        });
      }
      return;
    }
    try {
      final d = await Api.get('/notifications');
      if (!mounted) return;
      final list = (d['items'] as List).cast<Map<String, dynamic>>();
      setState(() {
        _items
          ..clear()
          ..addAll(list);
        _err = null;
        _loading = false;
      });
      // 打开就算读过
      if ((d['unread'] ?? 0) > 0) {
        for (final i in _items) {
          i['is_read'] = true;
        }
        await Api.post('/notifications/read', {});
        AppState.instance.refreshUnread();
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _err = e.message;
        _loading = false;
      });
    }
  }

  String _action(String kind) {
    switch (kind) {
      case 'reply':
        return '回复了你的線';
      case 'sub':
        return '回复了你';
      case 'agree':
        return '赞了你';
      case 'mention':
        return '在帖子里 @ 了你';
      case 'good':
        return '把你的線加精了';
      case 'del':
        return '删了你的内容';
      default:
        return '有新消息';
    }
  }

  IconData _icon(String kind) {
    switch (kind) {
      case 'agree':
        return Icons.thumb_up_alt_rounded;
      case 'sub':
        return Icons.subdirectory_arrow_right_rounded;
      case 'mention':
        return Icons.alternate_email_rounded;
      case 'good':
        return Icons.workspace_premium_rounded;
      case 'del':
        return Icons.delete_outline_rounded;
      default:
        return Icons.chat_bubble_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: widget.onMenu,
          icon: const Icon(Icons.menu_rounded),
          tooltip: '菜单',
        ),
        titleSpacing: 0,
        title: Text(
          '通知',
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    if (!AppState.instance.loggedIn) {
      return _Empty(
        icon: Icons.lock_outline_rounded,
        text: '登录后才能收到通知',
        hint: '去「我的」登录',
      );
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_err != null) {
      return _Empty(
        icon: Icons.cloud_off_rounded,
        text: _err!,
        hint: '点一下重试',
        onTap: () {
          setState(() {
            _loading = true;
            _err = null;
          });
          _load();
        },
      );
    }
    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 120),
            _Empty(
              icon: Icons.notifications_none_rounded,
              text: '还没有通知',
              hint: '别人回复你、赞你，会出现在这里',
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
        itemCount: _items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final n = _items[i];
          final actor = (n['actor'] ?? '') as String;
          final kind = (n['kind'] ?? '') as String;
          final body = (n['body'] ?? '') as String;
          final title = (n['thread_title'] ?? '') as String;
          final read = n['is_read'] == true;
          return Material(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                final tid = n['thread_id'];
                if (tid is int && tid > 0) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ThreadPage(
                        threadId: tid,
                        title: title,
                        focusPostId: n['reply_id'] is int
                            ? n['reply_id'] as int
                            : null,
                      ),
                    ),
                  );
                }
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Avatar(letter: actor.isEmpty ? '?' : actor[0], dim: read),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  actor,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: tt.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _action(kind),
                                style: tt.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                timeAgo((n['created_at'] ?? 0) as int),
                                style: tt.labelSmall?.copyWith(
                                  color: cs.outline,
                                ),
                              ),
                            ],
                          ),
                          if (body.isNotEmpty) ...[
                            const SizedBox(height: 5),
                            Text(
                              body,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: tt.bodyMedium?.copyWith(height: 1.4),
                            ),
                          ],
                          if (title.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(_icon(kind), size: 13, color: cs.outline),
                                const SizedBox(width: 5),
                                Expanded(
                                  child: Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: tt.labelSmall?.copyWith(
                                      color: cs.outline,
                                    ),
                                  ),
                                ),
                                if (!read)
                                  Container(
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                      color: cs.primary,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String letter;
  final bool dim;

  const _Avatar({required this.letter, required this.dim});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: dim ? cs.surfaceContainerHighest : cs.primaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        letter.toUpperCase(),
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: dim ? cs.onSurfaceVariant : cs.onPrimaryContainer,
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final IconData icon;
  final String text;
  final String hint;
  final VoidCallback? onTap;

  const _Empty({
    required this.icon,
    required this.text,
    required this.hint,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Center(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 52, color: cs.outlineVariant),
              const SizedBox(height: 14),
              Text(
                text,
                textAlign: TextAlign.center,
                style: tt.bodyMedium?.copyWith(color: cs.onSurface),
              ),
              const SizedBox(height: 6),
              Text(
                hint,
                textAlign: TextAlign.center,
                style: tt.bodySmall?.copyWith(color: cs.outline),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
