import 'package:flutter/material.dart';

import '../api.dart';
import '../widgets/page_width.dart';
import '../store.dart';
import '../widgets/app_card.dart';
import '../widgets/empty_view.dart';
import '../widgets/live_time.dart';

import 'thread_page.dart';

import '../l10n/error_text.dart';
import '../l10n/l10n.dart';

/// 站内消息：回复、楼中楼、赞。从「消息」列表点进来，不再是底栏 tab。
class NoticePage extends StatefulWidget {
  const NoticePage({super.key});

  @override
  State<NoticePage> createState() => _NoticePageState();
}

class _NoticePageState extends State<NoticePage> {
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
        _err = errorText(context, e);
        _loading = false;
      });
    }
  }

  String _action(String kind) => noticeActionText(kind);

  IconData _icon(String kind) => noticeIcon(kind);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Text(
          Lc.current.siteMessages,
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      body: PageWidth(child: _buildBody(context)),
    );
  }

  Widget _buildBody(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    if (!AppState.instance.loggedIn) {
      return EmptyView(
        icon: Icons.lock_outline_rounded,
        title: Lc.current.noticeLoginNeeded,
        hint: Lc.current.noticeLoginHint,
      );
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_err != null) {
      return EmptyView(
        icon: Icons.cloud_off_rounded,
        title: _err!,
        hint: Lc.current.tapToRetry,
        error: true,
        action: FilledButton.tonal(
          onPressed: () {
            setState(() {
              _loading = true;
              _err = null;
            });
            _load();
          },
          child: Text(Lc.current.retry),
        ),
      );
    }
    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: EmptyView(
          icon: Icons.notifications_none_rounded,
          title: Lc.current.noNotifications,
          hint: Lc.current.noNotificationsHint,
        ).scrollable(),
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
          return AppCard(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
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
                          LiveTime(
                            (n['created_at'] ?? 0) as int,
                            style: tt.labelSmall?.copyWith(color: cs.outline),
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

/// 站内消息一行摘要的动词：「回复了你的帖子」这类。
/// 消息列表和站内消息页共用，改文案只改这里。
String noticeActionText(String kind) {
  switch (kind) {
    case 'reply':
      return Lc.current.nRepliedPost;
    case 'sub':
      return Lc.current.nRepliedYou;
    case 'agree':
      return Lc.current.nLiked;
    case 'mention':
      return Lc.current.nMentioned;
    case 'good':
      return Lc.current.nFeatured;
    case 'del':
      return Lc.current.nDeleted;
    default:
      return Lc.current.nNew;
  }
}

IconData noticeIcon(String kind) {
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
