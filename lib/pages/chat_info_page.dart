import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../api.dart';
import '../chat_bg.dart';
import '../l10n/error_text.dart';
import '../l10n/l10n.dart';
import '../user_hue.dart';
import '../widgets/app_card.dart';
import '../widgets/app_sheet.dart';
import '../widgets/avatar.dart';
import '../widgets/page_width.dart';
import '../widgets/toast.dart';
import 'user_page.dart';

/// 聊天信息页交回去的东西。
///
/// 置顶、免打扰改了要立刻反映到顶栏；清空记录、换了背景要立刻反映到消息区；
/// 「查找聊天记录」得回聊天页才能弹出那个搜索面板。所以一页把这几件事一起带回去，
/// 聊天页拿一份结果照着改，不用再多问一次服务端。
class ChatInfoResult {
  final bool pinned;
  final bool muted;
  final bool cleared;
  final bool search;
  final String? bgPath;

  const ChatInfoResult({
    required this.pinned,
    required this.muted,
    required this.cleared,
    required this.search,
    this.bgPath,
  });
}

/// 聊天信息。照着微信那一页排的：头像名字、查找记录、免打扰、置顶、背景、清空。
///
/// 我们没群，所以没有「添加成员」；没有举报通道，投诉那栏也先不放。
class ChatInfoPage extends StatefulWidget {
  final Map<String, dynamic> peer;
  final int threadId;
  final bool pinned;
  final bool muted;
  final String? bgPath;

  const ChatInfoPage({
    super.key,
    required this.peer,
    required this.threadId,
    required this.pinned,
    required this.muted,
    this.bgPath,
  });

  @override
  State<ChatInfoPage> createState() => _ChatInfoPageState();
}

class _ChatInfoPageState extends State<ChatInfoPage> {
  late bool _pinned = widget.pinned;
  late bool _muted = widget.muted;
  late String? _bg = widget.bgPath;
  bool _cleared = false;
  bool _search = false;

  /// 连点开关会连发请求，改一半再改回来，状态就飘了。一次只放一个进去。
  bool _busy = false;

  String get _name =>
      (widget.peer['nickname'] ?? widget.peer['name'] ?? '') as String;
  String get _avatar => (widget.peer['avatar'] ?? '') as String;
  double get _hue => hueOfUser(widget.peer);

  ChatInfoResult _result() => ChatInfoResult(
    pinned: _pinned,
    muted: _muted,
    cleared: _cleared,
    search: _search,
    bgPath: _bg,
  );

  void _back() => Navigator.of(context).pop(_result());

  Future<void> _setState(
    Map<String, dynamic> body,
    void Function() apply,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await Api.post('/dm/${widget.threadId}/state', body);
      if (!mounted) return;
      setState(apply);
    } on ApiException catch (e) {
      if (!mounted) return;
      toast(context, errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openPeer() {
    final name = (widget.peer['name'] ?? '') as String;
    if (name.isEmpty) return;
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => UserPage(name: name)));
  }

  Future<void> _bgMenu() async {
    if (kIsWeb) {
      toast(context, Lc.current.backgroundWebUnsupported);
      return;
    }
    final l = Lc.current;
    final pick = await showAppSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(l.pickBackground),
              onTap: () => Navigator.pop(ctx, 'pick'),
            ),
            if (_bg != null)
              ListTile(
                leading: const Icon(Icons.hide_image_outlined),
                title: Text(l.clearBackground),
                onTap: () => Navigator.pop(ctx, 'clear'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (pick == null || !mounted) return;
    if (pick == 'clear') {
      await ChatBg.clear(widget.threadId);
      if (!mounted) return;
      setState(() => _bg = null);
      return;
    }
    final path = await ChatBg.pick(widget.threadId);
    if (!mounted) return;
    if (path == null) return;
    setState(() => _bg = path);
  }

  Future<void> _clearHistory() async {
    final l = Lc.current;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.clearChatHistory),
        content: Text(l.clearChatHistoryAsk),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.clearChatHistory),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    try {
      await Api.post('/dm/${widget.threadId}/clear', const {});
    } on ApiException catch (e) {
      if (!mounted) return;
      toast(context, errorText(context, e));
      return;
    }
    if (!mounted) return;
    toast(context, l.clearChatHistoryDone);
    _cleared = true;
    _back();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = Lc.current;
    return PopScope(
      // 系统返回键也要把结果带回去，不然改了置顶、返回后聊天页顶栏还是旧的。
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _back,
          ),
          title: Text(l.chatInfo),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
          children: [
            PageWidth(
              child: Column(
                children: [
                  AppCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    onTap: _openPeer,
                    child: Row(
                      children: [
                        CircleAvatarImg(
                          url: _avatar,
                          name: _name,
                          radius: 22,
                          hue: _hue,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Icon(Icons.chevron_right, color: cs.outline),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  AppCard(
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.manage_search_outlined),
                          title: Text(l.findInChat),
                          trailing: Icon(
                            Icons.chevron_right,
                            color: cs.outline,
                          ),
                          onTap: () {
                            _search = true;
                            _back();
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  AppCard(
                    child: Column(
                      children: [
                        SwitchListTile(
                          secondary: const Icon(Icons.volume_off_outlined),
                          title: Text(l.muteChat),
                          value: _muted,
                          onChanged: _busy
                              ? null
                              : (v) => _setState({'muted': v}, () {
                                  _muted = v;
                                }),
                        ),
                        Divider(height: 1, color: cs.outlineVariant),
                        SwitchListTile(
                          secondary: const Icon(Icons.push_pin_outlined),
                          title: Text(l.pinChat),
                          value: _pinned,
                          onChanged: _busy
                              ? null
                              : (v) => _setState({'pinned': v}, () {
                                  _pinned = v;
                                }),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  AppCard(
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.image_outlined),
                          title: Text(l.chatBackground),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_bg != null) ...[
                                Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    color: cs.surfaceContainerHighest,
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: ChatBg.image(context, _bg!),
                                ),
                                const SizedBox(width: 6),
                              ],
                              Icon(Icons.chevron_right, color: cs.outline),
                            ],
                          ),
                          onTap: _bgMenu,
                        ),
                        Divider(height: 1, color: cs.outlineVariant),
                        ListTile(
                          leading: Icon(
                            Icons.delete_sweep_outlined,
                            color: cs.error,
                          ),
                          title: Text(
                            l.clearChatHistory,
                            style: TextStyle(color: cs.error),
                          ),
                          onTap: _clearHistory,
                        ),
                      ],
                    ),
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
