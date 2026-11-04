import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../api.dart';
import '../img_compress.dart';
import '../l10n/error_text.dart';
import '../l10n/l10n.dart';
import '../store.dart';
import '../widgets/avatar.dart';
import '../widgets/toast.dart';
import 'user_page.dart';

/// 一对一私信。进页面拉最新 30 条，往上翻更早，15 秒轮询一次。
///
/// 样子照微信/QQ 来：自己的话靠右、对方靠左，每人一个头像，气泡带个小尾巴；
/// 隔了五分钟以上插一条时间；底部一条输入栏，有字才亮。
/// 聊天记录不长，全部放内存，翻到顶再向服务端要更早的。
class ChatPage extends StatefulWidget {
  final Map<String, dynamic> peer;

  const ChatPage({super.key, required this.peer});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  /// 气泡最多占屏宽多少。留出地方给头像，也留点呼吸。
  static const double _bubbleRatio = 0.68;

  final List<Map<String, dynamic>> _msgs = [];
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<Uint8List> _pending = [];
  final ImagePicker _picker = ImagePicker();

  Timer? _poll;

  bool _loading = true;
  bool _sending = false;
  bool _compressing = false;
  bool _hasMore = false;
  bool _loadingEarlier = false;
  bool _canSend = true;

  /// 人不在底部的时候来了新消息，压一个「有新消息」的按钮，不硬拉人下去。
  bool _newBelow = false;

  /// 正在引用哪一条。发出去就清掉。
  Map<String, dynamic>? _replyTo;

  String? _err;

  int get _peerId => (widget.peer['id'] ?? 0) as int;
  String get _peerName =>
      (widget.peer['nickname'] ?? widget.peer['name'] ?? '') as String;
  String get _peerAvatar => (widget.peer['avatar'] ?? '') as String;

  String get _myName =>
      (AppState.instance.user?['nickname'] ??
              AppState.instance.user?['name'] ??
              '')
          as String;
  String get _myAvatar => (AppState.instance.user?['avatar'] ?? '') as String;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load(initial: true);
    _poll = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted || _sending) return;
      _load();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _scroll.dispose();
    _input.dispose();
    super.dispose();
  }

  bool get _atBottom {
    if (!_scroll.hasClients) return true;
    final p = _scroll.position;
    return p.pixels > p.maxScrollExtent - 80;
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    if (p.pixels <= 24 && _hasMore && !_loadingEarlier) _loadEarlier();
    if (p.pixels > p.maxScrollExtent - 80 && _newBelow) {
      setState(() => _newBelow = false);
    }
  }

  void _toBottom({bool animate = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final end = _scroll.position.maxScrollExtent;
      if (animate) {
        _scroll.animateTo(
          end,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      } else {
        _scroll.jumpTo(end);
      }
    });
  }

  Future<void> _load({bool initial = false}) async {
    try {
      final d = await Api.get('/dm/$_peerId');
      if (!mounted) return;
      final list = (d['items'] as List).cast<Map<String, dynamic>>();
      final grew = _msgs.isNotEmpty && list.length > _msgs.length;
      final stay = !initial && _atBottom;
      setState(() {
        _msgs
          ..clear()
          ..addAll(list);
        _hasMore = d['has_more'] == true;
        _canSend = d['can_send'] != false;
        _loading = false;
        _err = null;
        if (grew && !_atBottom) _newBelow = true;
      });
      AppState.instance.refreshDmUnread();
      if (initial || stay) _toBottom();
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

  Future<void> _loadEarlier() async {
    if (_msgs.isEmpty || !_hasMore || _loadingEarlier) return;
    setState(() => _loadingEarlier = true);
    final before = (_msgs.first['id'] ?? 0) as int;
    final oldMax = _scroll.hasClients ? _scroll.position.maxScrollExtent : 0.0;
    final oldPix = _scroll.hasClients ? _scroll.position.pixels : 0.0;
    try {
      final d = await Api.get('/dm/$_peerId', query: {'before_id': '$before'});
      final list = (d['items'] as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _msgs.insertAll(0, list);
        _hasMore = d['has_more'] == true;
        _loadingEarlier = false;
      });
      // 往上插了东西，把位置补回去，画面别跳
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        final added = _scroll.position.maxScrollExtent - oldMax;
        _scroll.jumpTo(oldPix + added);
      });
    } catch (_) {
      if (mounted) setState(() => _loadingEarlier = false);
    }
  }

  Future<void> _pickImages() async {
    if (_pending.length >= 9 || _compressing) return;
    setState(() => _compressing = true);
    try {
      final picked = await _picker.pickMultiImage();
      final room = 9 - _pending.length;
      for (final x in picked.take(room)) {
        final raw = await x.readAsBytes();
        final b = await ImgCompress.run(raw);
        if (!ImgCompress.tooBig(b)) _pending.add(b);
      }
    } catch (e) {
      if (mounted) toast(context, Lc.current.readImageFailed('$e'));
    } finally {
      if (mounted) setState(() => _compressing = false);
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if ((text.isEmpty && _pending.isEmpty) || _sending) return;
    setState(() => _sending = true);
    try {
      // 先把图传上去，拿到站内地址再发消息
      final urls = <String>[];
      for (final b in _pending) {
        urls.add(await Api.uploadImage(b));
      }
      await Api.post('/dm/$_peerId', {
        'body': text,
        'images': urls,
        if (_replyTo != null) 'reply_id': _replyTo!['id'],
      });
      if (!mounted) return;
      _input.clear();
      setState(() {
        _pending.clear();
        _replyTo = null;
        _sending = false;
      });
      await _load();
      _toBottom(animate: true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      toast(context, errorText(context, e));
      // 403 多半是没互关、那条额度用完了。重新拉一次，输入栏会自己换掉。
      if (e.status == 403) _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      toast(context, '$e');
    }
  }

  void _openPeer() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UserPage(name: (widget.peer['name'] ?? '') as String),
      ),
    );
  }

  void _openMe() {
    final name = (AppState.instance.user?['name'] ?? '') as String;
    if (name.isEmpty) return;
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => UserPage(name: name)));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      appBar: AppBar(
        titleSpacing: 0,
        title: InkWell(
          onTap: _openPeer,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatarImg(url: _peerAvatar, name: _peerName, radius: 17),
                const SizedBox(width: 9),
                Flexible(
                  child: Text(
                    _peerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: _msgArea(cs)),
                if (_newBelow)
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: FilledButton.tonalIcon(
                      onPressed: () {
                        setState(() => _newBelow = false);
                        _toBottom(animate: true);
                      },
                      icon: const Icon(Icons.arrow_downward, size: 16),
                      label: Text(
                        Lc.current.dmNewMessages,
                        style: const TextStyle(fontSize: 12.5),
                      ),
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (_pending.isNotEmpty) _pendingBar(cs),
          _composer(cs),
        ],
      ),
    );
  }

  Widget _msgArea(ColorScheme cs) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_err != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_err!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: () {
                  setState(() => _loading = true);
                  _load(initial: true);
                },
                child: Text(Lc.current.retry),
              ),
            ],
          ),
        ),
      );
    }
    if (_msgs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline, size: 34, color: cs.outlineVariant),
            const SizedBox(height: 10),
            Text(
              Lc.current.dmNoChat,
              style: TextStyle(fontSize: 13, color: cs.outline),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
      itemCount: _msgs.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return SizedBox(
            height: 34,
            child: Center(
              child: _loadingEarlier
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
            ),
          );
        }
        return _row(cs, i - 1);
      },
    );
  }

  Widget _row(ColorScheme cs, int idx) {
    final m = _msgs[idx];
    final ts = (m['created_at'] ?? 0) as int;
    final prev = idx > 0 ? _msgs[idx - 1] : null;
    final pts = prev == null ? 0 : (prev['created_at'] ?? 0) as int;
    final showTime = prev == null || (ts - pts).abs() >= 300;
    final mine = (m['from_id'] ?? 0) == AppState.instance.user?['id'];
    final body = (m['body'] ?? '') as String;
    final imgs = (m['images'] as List? ?? const []).cast<String>();
    final reply = (m['reply'] as Map?)?.cast<String, dynamic>();
    final tight = prev != null && (ts - pts).abs() < 300;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showTime) _timePill(cs, ts),
        Padding(
          padding: EdgeInsets.only(top: tight ? 3 : 10),
          // 长按弹引用；点右边空白也管用，别只认气泡那小块
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPress: () => _msgMenu(m),
            child: Row(
              mainAxisAlignment: mine
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!mine) ...[
                  _avatar(_peerAvatar, _peerName, _openPeer),
                  const SizedBox(width: 7),
                ],
                Flexible(child: _bubble(cs, mine, body, imgs, reply)),
                if (mine) ...[
                  const SizedBox(width: 7),
                  _avatar(_myAvatar, _myName, _openMe),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _msgMenu(Map<String, dynamic> m) async {
    final body = (m['body'] ?? '') as String;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply),
              title: Text(Lc.current.quote),
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _replyTo = m);
              },
            ),
            if (body.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.copy),
                title: Text(Lc.current.copy),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: body));
                  Navigator.pop(ctx);
                  toast(context, Lc.current.copied);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _avatar(String url, String name, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: CircleAvatarImg(url: url, name: name, radius: 18),
    );
  }

  Widget _bubble(
    ColorScheme cs,
    bool mine,
    String body,
    List<String> imgs,
    Map<String, dynamic>? reply,
  ) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = mine
        ? cs.primary
        : (dark ? cs.surfaceContainerHighest : cs.surface);
    final fg = mine ? cs.onPrimary : cs.onSurface;
    final onlyImgs = body.isEmpty && imgs.isNotEmpty && reply == null;
    final maxW = MediaQuery.of(context).size.width * _bubbleRatio;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxW),
      child: IntrinsicWidth(
        child: _BubbleBox(
          color: bg,
          mine: mine,
          padding: onlyImgs
              ? const EdgeInsets.all(3)
              : const EdgeInsets.fromLTRB(11, 8, 11, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (reply != null) _quoteBlock(cs, mine, reply),
              if (imgs.isNotEmpty) _images(imgs),
              if (body.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(top: imgs.isEmpty ? 0 : 6),
                  child: SelectableText(
                    body,
                    style: TextStyle(fontSize: 15, height: 1.35, color: fg),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 气泡顶上那小块引用。不带竖线，靠底色和浅字区分，省得深色模式下糊成一片。
  Widget _quoteBlock(ColorScheme cs, bool mine, Map<String, dynamic> r) {
    final tint = mine ? cs.onPrimary : cs.onSurface;
    final name = (r['name'] ?? '') as String;
    final text = (r['body'] ?? '') as String;
    final summary = text.isNotEmpty
        ? text
        : (r['has_img'] == true ? Lc.current.replyImage : '');
    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.fromLTRB(7, 3, 8, 3),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$name: $summary',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          height: 1.3,
          color: tint.withValues(alpha: 0.78),
        ),
      ),
    );
  }

  Widget _images(List<String> imgs) {
    final one = imgs.length == 1;
    final side = one ? 168.0 : 104.0;
    return Wrap(
      spacing: 3,
      runSpacing: 3,
      children: [
        for (var i = 0; i < imgs.length; i++)
          GestureDetector(
            onTap: () => _viewImage(imgs, i),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(one ? 10 : 6),
              child: Image.network(
                Api.img(imgs[i]),
                width: side,
                height: side,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: side,
                  height: side,
                  color: Colors.black12,
                  child: const Icon(Icons.broken_image_outlined, size: 20),
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _viewImage(List<String> urls, int index) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, _, _) => _ImageViewer(urls: urls, index: index),
      ),
    );
  }

  Widget _timePill(ColorScheme cs, int ts) {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          _fmtTime(ts),
          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
        ),
      ),
    );
  }

  /// 今天只给时分，昨天往前加个字，再往前才写日期。
  String _fmtTime(int ts) {
    if (ts <= 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    final now = DateTime.now();
    final hm =
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    final day = DateTime(d.year, d.month, d.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return hm;
    if (diff == 1) return '${Lc.current.yesterday} $hm';
    if (d.year == now.year) return '${d.month}月${d.day}日 $hm';
    return '${d.year}年${d.month}月${d.day}日 $hm';
  }

  Widget _pendingBar(ColorScheme cs) {
    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        itemCount: _pending.length,
        separatorBuilder: (_, i) => const SizedBox(width: 8),
        itemBuilder: (context, i) => Stack(
          clipBehavior: Clip.none,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.memory(
                _pending[i],
                width: 60,
                height: 60,
                fit: BoxFit.cover,
              ),
            ),
            Positioned(
              right: -6,
              top: -6,
              child: GestureDetector(
                onTap: () => setState(() => _pending.removeAt(i)),
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(2),
                  child: const Icon(Icons.close, size: 14, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _composer(ColorScheme cs) {
    if (!_canSend) {
      return SafeArea(
        top: false,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: cs.surface,
            border: Border(
              top: BorderSide(
                color: cs.outlineVariant.withValues(alpha: 0.6),
                width: 0.5,
              ),
            ),
          ),
          child: Text(
            Lc.current.dmWaitReply,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
          ),
        ),
      );
    }

    final canSend =
        (_input.text.trim().isNotEmpty || _pending.isNotEmpty) && !_sending;
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border(
            top: BorderSide(
              color: cs.outlineVariant.withValues(alpha: 0.6),
              width: 0.5,
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_replyTo != null) _replyBar(cs),
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 6, 8, 6),
              child: _inputRow(cs, canSend),
            ),
          ],
        ),
      ),
    );
  }

  Widget _replyBar(ColorScheme cs) {
    final r = _replyTo!;
    final body = (r['body'] ?? '') as String;
    final hasImg = (r['images'] as List? ?? const []).isNotEmpty;
    final mine = (r['from_id'] ?? 0) == AppState.instance.user?['id'];
    final name = mine ? _myName : _peerName;
    final summary = body.isNotEmpty
        ? body
        : (hasImg ? Lc.current.replyImage : '');
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  Lc.current.replyTo(name),
                  style: TextStyle(fontSize: 11.5, color: cs.primary),
                ),
                const SizedBox(height: 1),
                Text(
                  summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => setState(() => _replyTo = null),
            icon: const Icon(Icons.close, size: 18),
            visualDensity: VisualDensity.compact,
            tooltip: Lc.current.cancel,
          ),
        ],
      ),
    );
  }

  Widget _inputRow(ColorScheme cs, bool canSend) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        IconButton(
          onPressed: (_sending || _compressing || _pending.length >= 9)
              ? null
              : _pickImages,
          tooltip: Lc.current.addImage,
          visualDensity: VisualDensity.compact,
          icon: _compressing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add_circle_outline, size: 26),
        ),
        Expanded(
          child: Container(
            constraints: const BoxConstraints(minHeight: 38),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: 5,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(fontSize: 15, height: 1.3),
              decoration: InputDecoration(
                isDense: true,
                hintText: Lc.current.saySomething,
                hintStyle: const TextStyle(fontSize: 15),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          height: 38,
          child: FilledButton(
            onPressed: canSend ? _send : null,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              minimumSize: const Size(0, 38),
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: _sending
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(Lc.current.send, style: const TextStyle(fontSize: 14)),
          ),
        ),
      ],
    );
  }
}

/// 气泡本体：圆角 + 靠头像那侧一个小尖。
class _BubbleBox extends StatelessWidget {
  const _BubbleBox({
    required this.color,
    required this.mine,
    required this.padding,
    required this.child,
  });

  final Color color;
  final bool mine;
  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    const r = Radius.circular(14);
    const small = Radius.circular(4);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: padding,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.only(
              topLeft: mine ? r : small,
              topRight: mine ? small : r,
              bottomLeft: r,
              bottomRight: r,
            ),
          ),
          child: child,
        ),
        Positioned(
          top: 9,
          left: mine ? null : -5,
          right: mine ? -5 : null,
          child: CustomPaint(
            size: const Size(6, 10),
            painter: _TailPainter(color, mine),
          ),
        ),
      ],
    );
  }
}

class _TailPainter extends CustomPainter {
  _TailPainter(this.color, this.mine);

  final Color color;
  final bool mine;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Path();
    if (mine) {
      p.moveTo(0, 0);
      p.lineTo(size.width, 0);
      p.lineTo(0, size.height);
    } else {
      p.moveTo(size.width, 0);
      p.lineTo(0, 0);
      p.lineTo(size.width, size.height);
    }
    p.close();
    canvas.drawPath(p, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_TailPainter old) =>
      old.color != color || old.mine != mine;
}

/// 图片全屏看。左右滑同一批图，点一下就关。
class _ImageViewer extends StatefulWidget {
  const _ImageViewer({required this.urls, required this.index});

  final List<String> urls;
  final int index;

  @override
  State<_ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<_ImageViewer> {
  late final PageController _pc = PageController(initialPage: widget.index);
  late int _i = widget.index;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Stack(
          children: [
            PageView.builder(
              controller: _pc,
              itemCount: widget.urls.length,
              onPageChanged: (i) => setState(() => _i = i),
              itemBuilder: (_, i) => Center(
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: Image.network(Api.img(widget.urls[i])),
                ),
              ),
            ),
            if (widget.urls.length > 1)
              Positioned(
                bottom: 28,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${_i + 1}/${widget.urls.length}',
                      style: const TextStyle(fontSize: 12, color: Colors.white),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
