import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart' hide PickedFile;

import '../api.dart';
import '../poller.dart';
import '../cloud.dart';
import '../file_browser.dart';
import '../file_pick.dart';
import '../img_compress.dart';
import '../l10n/error_text.dart';
import '../l10n/l10n.dart';
import '../plat.dart';
import '../store.dart';
import '../widgets/empty_view.dart';
import '../widgets/app_sheet.dart';
import '../widgets/page_width.dart';
import '../widgets/avatar.dart';
import '../widgets/file_card.dart';
import '../widgets/toast.dart';
import 'cloud_pick_page.dart';
import 'gallery_picker_page.dart';
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
  static const double _bubbleRatio = 0.72;

  final List<Map<String, dynamic>> _msgs = [];
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<Uint8List> _pending = [];

  /// 待发的附件。和图分开存，发的时候一起送上去。
  final List<PostFile> _pendingFiles = [];
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
    // 告诉轮询：这个人的消息别弹，人正看着呢。
    Poller.instance.activePeer = _peerId;
    _scroll.addListener(_onScroll);
    _load(initial: true);
    _poll = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted || _sending) return;
      _load();
    });
  }

  @override
  void dispose() {
    if (Poller.instance.activePeer == _peerId) {
      Poller.instance.activePeer = 0;
    }
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

  /// 加号：微信那种小面板，图片和文件分开走。
  Future<void> _attachMenu() async {
    await showAppSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Row(
            children: [
              _attachTile(
                ctx,
                Icons.photo_library_outlined,
                Lc.current.dmPickImage,
                () {
                  Navigator.pop(ctx);
                  _pickImages();
                },
              ),
              const SizedBox(width: 24),
              _attachTile(ctx, Icons.attach_file, Lc.current.dmPickFile, () {
                Navigator.pop(ctx);
                _pickFile();
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _attachTile(
    BuildContext ctx,
    IconData icon,
    String label,
    VoidCallback onTap,
  ) {
    final cs = Theme.of(ctx).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 26, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImages() async {
    if (_pending.length >= 9 || _compressing) return;
    setState(() => _compressing = true);
    try {
      // 手机上有自己的相册页就用它，网页版没有 MediaStore，退回系统选择
      List<XFile> picked;
      if (!hasMediaStore) {
        picked = await _picker.pickMultiImage();
      } else {
        final r = await Navigator.of(context).push<List<XFile>>(
          MaterialPageRoute(
            builder: (_) => GalleryPickerPage(maxCount: 9 - _pending.length),
          ),
        );
        picked = r ?? const <XFile>[];
      }
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

  /// 文件从哪来：云盘里现成的，还是设备上挑新的。
  Future<String?> _fileSource() {
    return showAppSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.cloud_outlined),
              title: Text(Lc.current.pickFromCloud),
              onTap: () => Navigator.of(c).pop('cloud'),
            ),
            ListTile(
              leading: const Icon(Icons.smartphone),
              title: Text(Lc.current.pickFromDevice),
              onTap: () => Navigator.of(c).pop('device'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  int get _fileRoom => 5 - _pendingFiles.length;

  Future<void> _pickFile() async {
    if (_sending || _compressing) return;
    final src = await _fileSource();
    if (!mounted || src == null) return;
    if (src == 'cloud') {
      await _addFromCloud();
      return;
    }
    await _pickFromDevice();
  }

  Future<void> _addFromCloud() async {
    final left = _fileRoom;
    if (left <= 0) {
      toast(context, Lc.current.attachMax('5'));
      return;
    }
    final picked = await Navigator.of(context).push<List<CloudFile>>(
      MaterialPageRoute(builder: (_) => CloudPickPage(maxCount: left)),
    );
    if (!mounted || picked == null || picked.isEmpty) return;
    setState(() {
      for (final f in picked.take(left)) {
        _pendingFiles.add(PostFile(url: f.url, name: f.name, size: f.size));
      }
    });
  }

  /// 设备上的文件：手机上用自己的浏览器翻，网页版没这能力，退回系统选择器。
  Future<void> _pickFromDevice() async {
    final left = _fileRoom;
    if (left <= 0) {
      toast(context, Lc.current.attachMax('5'));
      return;
    }
    List<PickedFile> list = const [];
    if (fileBrowserSupported) {
      final r = await Navigator.of(context).push<List<PickedFile>>(
        MaterialPageRoute(
          builder: (_) => const FileBrowserPage(pickOnly: true),
        ),
      );
      list = r ?? const <PickedFile>[];
    } else {
      final f = await pickFile();
      if (f != null) list = [f];
    }
    if (!mounted || list.isEmpty) return;
    await _uploadFiles(list.take(left).toList());
  }

  Future<void> _uploadFiles(List<PickedFile> list) async {
    if (list.isEmpty) return;
    setState(() => _compressing = true);
    try {
      for (final f in list) {
        final d = await Api.uploadFile(f);
        if (!mounted) return;
        setState(() {
          _pendingFiles.add(
            PostFile(
              url: '${d['url']}',
              name: '${d['name']}',
              size: d['size'] is int ? d['size'] as int : f.size,
            ),
          );
        });
      }
    } on ApiException catch (e) {
      if (mounted) toast(context, errorText(context, e));
    } catch (e) {
      if (mounted) toast(context, '$e');
    } finally {
      if (mounted) setState(() => _compressing = false);
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if ((text.isEmpty && _pending.isEmpty && _pendingFiles.isEmpty) ||
        _sending) {
      return;
    }
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
        if (_pendingFiles.isNotEmpty)
          'files': _pendingFiles.map((f) => f.toJson()).toList(),
        if (_replyTo != null) 'reply_id': _replyTo!['id'],
      });
      if (!mounted) return;
      _input.clear();
      setState(() {
        _pending.clear();
        _pendingFiles.clear();
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
      body: PageWidth(
        child: Column(
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
            if (_pending.isNotEmpty || _pendingFiles.isNotEmpty)
              _pendingBar(cs),
            _composer(cs),
          ],
        ),
      ),
    );
  }

  Widget _msgArea(ColorScheme cs) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_err != null) {
      return EmptyView(
        icon: Icons.cloud_off_rounded,
        title: _err!,
        error: true,
        action: FilledButton.tonal(
          onPressed: () {
            setState(() => _loading = true);
            _load(initial: true);
          },
          child: Text(Lc.current.retry),
        ),
      );
    }
    if (_msgs.isEmpty) {
      return EmptyView(
        icon: Icons.chat_bubble_outline,
        title: Lc.current.dmNoChat,
      );
    }
    // 点消息区任意空白、或者开始往上翻，都收键盘
    return NotificationListener<ScrollStartNotification>(
      onNotification: (_) {
        FocusScope.of(context).unfocus();
        return false;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView.builder(
          controller: _scroll,
          // 内容不满一屏也能拖，拖到边上有回弹，跟 QQ 微信一个手感
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
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
        ),
      ),
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
    final files = PostFile.listOf(m['files']);
    final reply = (m['reply'] as Map?)?.cast<String, dynamic>();
    final tight = prev != null && (ts - pts).abs() < 300;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showTime) _timePill(cs, ts),
        Padding(
          padding: EdgeInsets.only(top: tight ? 6 : 21, left: 2, right: 2),
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
                  const SizedBox(width: 7.5),
                ],
                Flexible(child: _bubble(cs, mine, body, imgs, files, reply)),
                if (mine) ...[
                  const SizedBox(width: 7.5),
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
    await showAppSheet<void>(
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
    List<PostFile> files,
    Map<String, dynamic>? reply,
  ) {
    // 自己的用主题色，对方的用主题色的容器色，两边都在全局配色里
    final bg = mine ? cs.primary : cs.primaryContainer;
    final fg = mine ? cs.onPrimary : cs.onPrimaryContainer;
    final onlyImgs =
        body.isEmpty && imgs.isNotEmpty && files.isEmpty && reply == null;
    final maxW = MediaQuery.of(context).size.width * _bubbleRatio;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxW),
      child: IntrinsicWidth(
        child: _BubbleBox(
          color: bg,
          // 纯图片几乎贴边；带图文的，图片也只留一点点，文字另外缩进
          padding: onlyImgs ? const EdgeInsets.all(3) : const EdgeInsets.all(4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (reply != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 1, 6, 0),
                  child: _quoteBlock(cs, mine, reply),
                ),
              if (imgs.isNotEmpty) _images(imgs),
              if (files.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                  child: FileCards(files: files),
                ),
              if (body.isNotEmpty)
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    9,
                    (imgs.isEmpty && files.isEmpty) ? 2 : 7,
                    9,
                    3,
                  ),
                  child: SelectableText(
                    body,
                    style: TextStyle(fontSize: 15.5, height: 1.42, color: fg),
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
    final tint = mine ? cs.onPrimary : cs.onPrimaryContainer;
    final name = (r['name'] ?? '') as String;
    final text = (r['body'] ?? '') as String;
    final summary = text.isNotEmpty
        ? text
        : (r['has_img'] == true ? Lc.current.replyImage : '');
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(8, 4, 9, 4),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(color: tint.withValues(alpha: 0.55), width: 2.5),
        ),
      ),
      child: Text(
        '$name: $summary',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12.5,
          height: 1.32,
          color: tint.withValues(alpha: 0.75),
        ),
      ),
    );
  }

  Widget _images(List<String> imgs) {
    final one = imgs.length == 1;
    final side = one ? 172.0 : 106.0;
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (var i = 0; i < imgs.length; i++)
          GestureDetector(
            onTap: () => _viewImage(imgs, i),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(one ? 13 : 9),
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
        margin: const EdgeInsets.only(top: 21),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          _fmtTime(ts),
          style: TextStyle(
            fontSize: 11.5,
            color: cs.onSurfaceVariant,
            height: 1.2,
          ),
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
        itemCount: _pending.length + _pendingFiles.length,
        separatorBuilder: (_, i) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          if (i >= _pending.length) {
            final fi = i - _pending.length;
            return _fileTile(cs, _pendingFiles[fi], () {
              setState(() => _pendingFiles.removeAt(fi));
            });
          }
          return Stack(
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
                    child: const Icon(
                      Icons.close,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 待发区里的一个附件。和图一样，右上角能删。
  Widget _fileTile(ColorScheme cs, PostFile f, VoidCallback onRemove) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 172,
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Icon(fileIconFor(f.name), size: 22, color: cs.primary),
              const SizedBox(width: 7),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      f.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5),
                    ),
                    Text(
                      f.sizeText,
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Positioned(
          right: -6,
          top: -6,
          child: GestureDetector(
            onTap: onRemove,
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
        (_input.text.trim().isNotEmpty ||
            _pending.isNotEmpty ||
            _pendingFiles.isNotEmpty) &&
        !_sending;
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
    final hasImg =
        (r['images'] as List? ?? const []).isNotEmpty ||
        (r['files'] as List? ?? const []).isNotEmpty;
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
          onPressed: _sending ? null : _attachMenu,
          tooltip: Lc.current.addImage,
          visualDensity: VisualDensity.compact,
          icon: _compressing
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add_circle_outline, size: 27),
        ),
        Expanded(
          child: Container(
            constraints: const BoxConstraints(minHeight: 42),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
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
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          height: 42,
          child: FilledButton(
            onPressed: canSend ? _send : null,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              minimumSize: const Size(0, 42),
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
/// 气泡壳。统一 16 的圆角，不再画尖角——尖角配小圆角显脏。
class _BubbleBox extends StatelessWidget {
  const _BubbleBox({
    required this.color,
    required this.padding,
    required this.child,
  });

  final Color color;
  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.20 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
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
