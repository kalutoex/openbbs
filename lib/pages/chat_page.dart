import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart' hide PickedFile;
import 'package:shared_preferences/shared_preferences.dart';

import '../api.dart';
import '../haptics.dart';
import '../poller.dart';
import '../cloud.dart';
import '../file_browser.dart';
import '../file_pick.dart';
import '../img_compress.dart';
import '../l10n/error_text.dart';
import '../l10n/l10n.dart';
import '../plat.dart';
import '../user_hue.dart';
import '../store.dart';
import '../widgets/empty_view.dart';
import '../widgets/app_sheet.dart';
import '../widgets/page_width.dart';
import '../widgets/retry_image.dart';
import '../widgets/avatar.dart';
import '../widgets/file_card.dart';
import '../widgets/post_images.dart';
import '../widgets/toast.dart';
import 'cloud_pick_page.dart';
import 'gallery_picker_page.dart';
import 'user_page.dart';

/// 一对一私信。
///
/// 这一版整体重写，样子还是照微信/QQ 来，但把缺的补上了：
/// 日期分隔、长按菜单（引用/复制/撤回/删除/多选）、撤回、单条删除、
/// 会话内搜索、表情面板、草稿、滚到底的浮标、自己最后一条的「已读」。
///
/// 记录不长，全部放内存；翻到顶再向服务端要更早的，15 秒轮询一次。
class ChatPage extends StatefulWidget {
  final Map<String, dynamic> peer;

  const ChatPage({super.key, required this.peer});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  /// 撤回时限，跟服务端 DM_RECALL_WINDOW 对齐。客户端先挡一下，省一次白跑。
  static const int _recallSeconds = 120;

  /// 气泡最宽占多少屏宽。宽屏另有限宽，别让人一行读半屏。
  static const double _bubbleRatio = 0.72;

  final List<Map<String, dynamic>> _msgs = [];
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _focus = FocusNode();
  final List<Uint8List> _pending = [];

  /// 待发的附件。和图分开存，发的时候一起送上去。
  final List<PostFile> _pendingFiles = [];
  final ImagePicker _picker = ImagePicker();

  Timer? _poll;
  Timer? _draftTimer;

  bool _loading = true;

  bool _sending = false;

  /// 发多张图时走到第几张了。按钮上直接显示 2/9，人就知道它在动。
  int _sendAt = 0;
  int _sendTotal = 0;

  /// 上一次发送失败留下的东西。图传上去的那几张记着地址，
  /// 重发时直接拿来用，不从头上再传一遍。
  List<String> _failedUrls = const [];
  List<PostFile> _failedFiles = const [];
  Map<String, dynamic>? _failedReply;
  String _failedWhy = '';
  bool _compressing = false;
  bool _hasMore = false;
  bool _loadingEarlier = false;
  bool _canSend = true;
  bool _showEmoji = false;

  /// 多选模式：点气泡勾选，顶上换成「已选 N 条 + 删除」。
  bool _multi = false;
  final Set<int> _sel = {};

  /// 人不在底部的时候来了几条新的，压一个浮标，不硬把人拉下去。
  bool _atBottom = true;
  int _newCount = 0;

  /// 正在引用哪一条。发出去就清掉。
  Map<String, dynamic>? _replyTo;

  /// 每条消息气泡的 key，长按菜单要拿它的位置来贴。
  final Map<int, GlobalKey> _bubbleKeys = {};

  /// 长按中的那条，气泡压一下，给个按住的反馈。
  int? _pressedId;

  /// 上次看到哪条。进会话时比这更新的第一条上面拉一条「以下是新消息」。
  int _unreadFromId = 0;

  String? _err;

  /// 双方的主题色。对方那份每次拉取都刷新，可能人家刚换过。
  late double _peerHue = hueOfUser(widget.peer);
  double get _myHue => AppState.instance.accentHue.value;

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
  int get _myId => (AppState.instance.user?['id'] ?? 0) as int;

  /// 私信草稿也带账号：peerId 是每座站各自编的，光靠它两个账号会互相覆盖。
  String get _draftKey => 'dm_draft_u${_myId}_$_peerId';

  @override
  void initState() {
    super.initState();
    // 告诉轮询：这个人的消息别弹，人正看着呢。
    Poller.instance.activePeer = _peerId;
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_onScroll);
    _focus.addListener(() {
      if (_focus.hasFocus && _showEmoji) setState(() => _showEmoji = false);
    });
    _restoreDraft();
    _load(initial: true);
    _poll = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted || _sending) return;
      _load();
    });
    // 全站轮询 5 秒一趟，它一发现这个会话有新消息就敲一下。
    // 只靠上面那个 15 秒的定时器，对方刚发完得干等十几秒才看见。
    Poller.instance.dmSignal.addListener(_onPollerSignal);
  }

  @override
  void dispose() {
    if (Poller.instance.activePeer == _peerId) {
      Poller.instance.activePeer = 0;
    }
    WidgetsBinding.instance.removeObserver(this);
    _flushDraft();
    _poll?.cancel();
    Poller.instance.dmSignal.removeListener(_onPollerSignal);
    _draftTimer?.cancel();
    _scroll.dispose();
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// 连着几轮补增量了。撤回和「对方删了」改的是已经落屏的那几条，
  /// 增量接口看不见，隔十来轮全量扫一遍补上。
  int _pollTicks = 0;

  void _onPollerSignal() {
    if (!mounted || _sending) return;
    _pollTicks++;
    if (_pollTicks % 10 == 0 && _atBottom) {
      _load();
      return;
    }
    _loadNew();
  }

  /// 只补比手上最后一条更新的。一秒一轮时全量重拉会把整段消息重建，
  /// 图片跟着闪，流量也白花。
  Future<void> _loadNew() async {
    if (_fetching) {
      _reloadPending = true;
      return;
    }
    if (_msgs.isEmpty) return _load();
    _fetching = true;
    try {
      final lastId = (_msgs.last['id'] ?? 0) as int;
      final d = await Api.get('/dm/$_peerId', query: {'after_id': '$lastId'});
      if (!mounted) return;
      final list = (d['items'] as List).cast<Map<String, dynamic>>();
      if (list.isEmpty) {
        final canSend = d['can_send'] != false;
        if (canSend != _canSend) setState(() => _canSend = canSend);
        return;
      }
      final stay = _isBottom();
      setState(() {
        _msgs.addAll(list);
        _canSend = d['can_send'] != false;
        if (!stay) _newCount += list.length;
      });
      AppState.instance.refreshDmUnread();
      unawaited(_markSeen());
      if (stay) _toBottom();
    } catch (_) {
      // 这一轮没拉上就算了，下一秒接着来
    } finally {
      _fetching = false;
      if (_reloadPending && mounted) {
        _reloadPending = false;
        unawaited(_loadNew());
      }
    }
  }

  /// reverse 列表，offset 0 就是最底下（最新一条）。
  bool _isBottom() {
    if (!_scroll.hasClients) return true;
    return _scroll.position.pixels <= 80;
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    // 到顶了（offset 跑到最大）就该翻更早的
    if (p.pixels >= p.maxScrollExtent - 24 && _hasMore && !_loadingEarlier) {
      _loadEarlier();
    }
    final bottom = _isBottom();
    if (bottom != _atBottom) {
      setState(() {
        _atBottom = bottom;
        if (bottom) _newCount = 0;
      });
    }
  }

  /// 键盘弹上弹下会改可视高度，列表跟着缩，最后一条常被挤出屏幕。
  /// 本来就停在底部的，重新贴回去；人在翻旧消息就别拽他。
  @override
  void didChangeMetrics() {
    if (!_atBottom) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _toBottom();
    });
  }

  void _toBottom({bool animate = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      const end = 0.0;
      if (animate) {
        _scroll.animateTo(
          end,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      } else {
        _scroll.jumpTo(end);
      }
      if (_newCount != 0) setState(() => _newCount = 0);
    });
  }

  // ── 草稿 ─────────────────────────────────────────────
  // 退出再进来，没发出去的字还在。之前手滑按返回就白打了。

  Future<void> _restoreDraft() async {
    final p = await SharedPreferences.getInstance();
    final d = p.getString(_draftKey);
    if (d == null || d.isEmpty || !mounted) return;
    _input.text = d;
    setState(() {});
  }

  void _saveDraftSoon() {
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 400), _flushDraft);
  }

  Future<void> _flushDraft() async {
    final p = await SharedPreferences.getInstance();
    final t = _input.text;
    if (t.trim().isEmpty) {
      await p.remove(_draftKey);
    } else {
      await p.setString(_draftKey, t);
    }
  }

  // ── 拉取 ─────────────────────────────────────────────

  /// 一趟还没回来就又来一趟，会两次 setState 换数据，画面就抖一下。
  /// 记下来等这趟完事再补一次，别并行。
  bool _fetching = false;
  bool _reloadPending = false;

  Future<void> _load({bool initial = false}) async {
    if (_fetching) {
      _reloadPending = true;
      return;
    }
    _fetching = true;
    try {
      final seen = initial ? await _lastSeen() : 0;
      final d = await Api.get('/dm/$_peerId');
      if (!mounted) return;
      final list = (d['items'] as List).cast<Map<String, dynamic>>();
      final prevLen = _msgs.length;
      final prevLast = prevLen == 0 ? 0 : (_msgs.last['id'] ?? 0) as int;
      final stay = !initial && _isBottom();
      var fresh = 0;
      for (final m in list) {
        if (((m['id'] ?? 0) as int) > prevLast) fresh++;
      }
      final peer = (d['peer'] as Map?)?.cast<String, dynamic>();
      // 上次离开之后才来的消息，从第一条开始划线
      var lineId = 0;
      if (initial && seen > 0) {
        for (final m in list) {
          final id = (m['id'] ?? 0) as int;
          if (id > seen) {
            lineId = id;
            break;
          }
        }
      }
      setState(() {
        if (initial) _unreadFromId = lineId;
        if (peer != null) _peerHue = hueOfUser(peer);
        _msgs
          ..clear()
          ..addAll(list);
        _hasMore = d['has_more'] == true;
        _canSend = d['can_send'] != false;
        _loading = false;
        _err = null;
        if (fresh > 0 && !stay) _newCount += fresh;
        if (list.isEmpty) _multi = false;
        // 选中的消息没了（撤回/删除）就从选择里剔掉
        final ids = list.map((e) => (e['id'] ?? 0) as int).toSet();
        _sel.removeWhere((id) => !ids.contains(id));
      });
      AppState.instance.refreshDmUnread();
      if (initial) _markSeen();
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
    } finally {
      _fetching = false;
      if (_reloadPending && mounted) {
        _reloadPending = false;
        unawaited(_load());
      }
    }
  }

  Future<int> _lastSeen() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt('dm_seen_$_peerId') ?? 0;
  }

  /// 进来就算看过。老规矩，没看完也认，省得下次一堆「新消息」压着。
  Future<void> _markSeen() async {
    if (_msgs.isEmpty) return;
    final last = (_msgs.last['id'] ?? 0) as int;
    if (last <= 0) return;
    final p = await SharedPreferences.getInstance();
    await p.setInt('dm_seen_$_peerId', last);
  }

  Future<void> _loadEarlier() async {
    if (_msgs.isEmpty || !_hasMore || _loadingEarlier) return;
    setState(() => _loadingEarlier = true);
    final before = (_msgs.first['id'] ?? 0) as int;
    try {
      final d = await Api.get('/dm/$_peerId', query: {'before_id': '$before'});
      final list = (d['items'] as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _msgs.insertAll(0, list);
        _hasMore = d['has_more'] == true;
        _loadingEarlier = false;
      });
      // reverse 列表往顶部插内容，视口本来就不动，不用再补偏移。
    } catch (_) {
      if (mounted) setState(() => _loadingEarlier = false);
    }
  }

  // ── 附件 ─────────────────────────────────────────────

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
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
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

  // ── 发送 ─────────────────────────────────────────────

  Future<void> _send() async {
    final text = _input.text.trim();
    if ((text.isEmpty && _pending.isEmpty && _pendingFiles.isEmpty) ||
        _sending) {
      return;
    }
    setState(() {
      _sending = true;
      _sendTotal = _pending.length;
      _sendAt = _failedUrls.length;
    });
    // 重发时前面几张已经传好了，接着往下排，别整批重来
    final urls = <String>[..._failedUrls];
    final files = _failedFiles.isNotEmpty ? _failedFiles : _pendingFiles;
    final reply = _replyTo ?? _failedReply;
    String why = '';
    try {
      // 先把图传上去，拿到站内地址再发消息
      for (var i = urls.length; i < _pending.length; i++) {
        if (mounted) setState(() => _sendAt++);
        urls.add(await Api.uploadImage(_pending[i]));
      }
      await Api.post('/dm/$_peerId', {
        'body': text,
        'images': urls,
        if (files.isNotEmpty) 'files': files.map((f) => f.toJson()).toList(),
        if (reply != null) 'reply_id': reply['id'],
      });
      if (!mounted) return;
      Haptics.done();
      _input.clear();
      await _flushDraft();
      setState(() {
        _pending.clear();
        _pendingFiles.clear();
        _replyTo = null;
        _sending = false;
        _sendAt = 0;
        _sendTotal = 0;
        _showEmoji = false;
        _failedUrls = const [];
        _failedFiles = const [];
        _failedReply = null;
        _failedWhy = '';
      });
      await _load();
      _toBottom(animate: true);
    } on ApiException catch (e) {
      if (mounted) why = errorText(context, e);
      if (mounted) {
        // 403 多半是没互关、那条额度用完了。重新拉一次，输入栏会自己换掉。
        if (e.status == 403) _load();
      }
    } catch (e) {
      why = '$e';
    }
    if (!mounted) return;
    setState(() {
      _sending = false;
      _sendAt = 0;
      _sendTotal = 0;
      // 东西都留着，条子上点一下就再来一次
      _failedUrls = urls;
      _failedFiles = files;
      _failedReply = reply;
      _failedWhy = why;
    });
  }

  void _dropFailed() {
    setState(() {
      _failedUrls = const [];
      _failedFiles = const [];
      _failedReply = null;
      _failedWhy = '';
    });
  }

  // ── 单条操作 ──────────────────────────────────────────

  bool _canRecall(Map<String, dynamic> m) {
    if ((m['from_id'] ?? 0) != _myId) return false;
    if (m['recalled'] == true) return false;
    final ts = (m['created_at'] ?? 0) as int;
    return DateTime.now().millisecondsSinceEpoch ~/ 1000 - ts <= _recallSeconds;
  }

  Future<void> _recall(Map<String, dynamic> m) async {
    try {
      await Api.post('/dm/msg/${m['id']}/recall', const {});
      if (!mounted) return;
      await _load();
    } on ApiException catch (e) {
      if (mounted) toast(context, errorText(context, e));
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
  }

  Future<void> _deleteOne(Map<String, dynamic> m) async {
    final id = (m['id'] ?? 0) as int;
    try {
      await Api.post('/dm/msg/$id/del', const {});
      if (!mounted) return;
      setState(() => _msgs.removeWhere((e) => (e['id'] ?? 0) == id));
      if (_replyTo != null && (_replyTo!['id'] ?? 0) == id) {
        setState(() => _replyTo = null);
      }
    } on ApiException catch (e) {
      if (mounted) toast(context, errorText(context, e));
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
  }

  /// 长按菜单：引用、复制、添加到云盘、撤回、删除、多选。一条消息能做的事都在这儿。
  /// 长按菜单：微信那种贴着气泡的横条，不是弹整页。
  Future<void> _msgMenu(Map<String, dynamic> m) async {
    final body = (m['body'] ?? '') as String;
    final recalled = m['recalled'] == true;
    if (recalled) return;
    final id = (m['id'] ?? 0) as int;
    final mine = (m['from_id'] ?? 0) == _myId;
    final files = PostFile.listOf(m['files']);
    final actions = <_MsgAction>[
      _MsgAction(Icons.reply, Lc.current.quote, () {
        setState(() => _replyTo = m);
        _focus.requestFocus();
      }),
      if (body.isNotEmpty)
        _MsgAction(Icons.copy, Lc.current.copy, () {
          Clipboard.setData(ClipboardData(text: body));
          toast(context, Lc.current.copied);
        }),
      if (files.isNotEmpty)
        _MsgAction(
          Icons.cloud_upload_outlined,
          Lc.current.saveToCloud,
          () => _saveToCloud(files),
        ),
      if (_canRecall(m))
        _MsgAction(Icons.undo, Lc.current.dmRecall, () => _recall(m)),
      _MsgAction(Icons.delete_outline, Lc.current.delete, () => _deleteOne(m)),
      _MsgAction(Icons.checklist, Lc.current.dmMulti, () {
        setState(() {
          _multi = true;
          _sel
            ..clear()
            ..add(id);
        });
      }),
    ];
    await _showBubbleMenu(id, actions, mine: mine);
  }

  /// 聊天里的附件收进自己云盘。服务端手里已经有这份内容，只挂一条账本，
  /// 不用把文件再下下来传一遍。多个文件一起收，最后只说一句结果。
  Future<void> _saveToCloud(List<PostFile> files) async {
    var added = 0;
    Object? err;
    for (final f in files) {
      try {
        final d = await CloudApi.claim(f.url);
        if (d['exists'] != true) added++;
      } catch (e) {
        err = e;
      }
    }
    if (!mounted) return;
    if (err != null) {
      toast(context, errorText(context, err));
      return;
    }
    toast(
      context,
      added > 0 ? Lc.current.addedToCloud : Lc.current.alreadyInCloud,
    );
  }

  /// 贴着气泡弹出的横排工具条：算好位置，上下翻，带一个指向气泡的小三角。
  Future<void> _showBubbleMenu(
    int id,
    List<_MsgAction> actions, {
    required bool mine,
  }) async {
    if (actions.isEmpty) return;
    final box = _bubbleKeys[id]?.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final origin = box.localToGlobal(Offset.zero);
    final r = origin & box.size;

    final screen = MediaQuery.of(context).size;
    final topPad = MediaQuery.of(context).padding.top;
    const barH = 52.0;
    const arrowH = 7.0;
    final itemW = ((screen.width - 16) / actions.length).clamp(46.0, 63.0);
    final barW = itemW * actions.length;

    var left = mine ? r.right - barW : r.left;
    left = left.clamp(8.0, (screen.width - barW - 8).clamp(8.0, screen.width));
    // 上面放得下就放上面，贴着气泡；放不下翻到下面。
    final above = r.top - barH - arrowH - 10 >= topPad;
    final top = above ? r.top - barH - arrowH - 4 : r.bottom + arrowH + 4;
    final arrowX = (r.center.dx - left).clamp(20.0, barW - 20.0);

    Haptics.press();
    setState(() => _pressedId = id);
    final picked = await showGeneralDialog<_MsgAction>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black.withValues(alpha: 0.04),
      transitionDuration: const Duration(milliseconds: 130),
      pageBuilder: (ctx, _, _) {
        final dark = Theme.of(ctx).brightness == Brightness.dark;
        final bg = dark ? const Color(0xFF2C2C2E) : Colors.white;
        final fg = dark ? const Color(0xFFEDEDED) : const Color(0xFF1B1B1B);
        // 工具条自己是个独立的浮层。不套一层 Material，Text 在 debug 下会
        // 画出黄色双下划线，InkResponse 的水波也没有落点。
        return Material(
          type: MaterialType.transparency,
          child: Stack(
            children: [
              Positioned(
                left: left,
                top: top,
                child: SizedBox(
                  width: barW,
                  height: barH + arrowH,
                  child: CustomPaint(
                    painter: _MsgMenuPainter(
                      bg: bg,
                      above: above,
                      arrowX: arrowX,
                      barH: barH,
                      arrowH: arrowH,
                    ),
                    child: Padding(
                      padding: EdgeInsets.only(
                        top: above ? 0 : arrowH,
                        bottom: above ? arrowH : 0,
                      ),
                      child: Row(
                        children: [
                          for (final a in actions)
                            SizedBox(
                              width: itemW,
                              height: barH,
                              child: InkResponse(
                                radius: 26,
                                onTap: () => Navigator.pop(ctx, a),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(a.icon, size: 19, color: fg),
                                    const SizedBox(height: 3),
                                    Text(
                                      a.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: fg,
                                        height: 1.15,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
      transitionBuilder: (ctx, anim, _, child) {
        final t = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: t,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1).animate(t),
            child: child,
          ),
        );
      },
    );
    if (mounted) setState(() => _pressedId = null);
    picked?.run();
  }

  void _toggleSel(int id) {
    setState(() {
      if (!_sel.add(id)) _sel.remove(id);
      if (_sel.isEmpty) _multi = false;
    });
  }

  void _exitMulti() {
    setState(() {
      _multi = false;
      _sel.clear();
    });
  }

  /// 多选删除走逐条接口。私信一次删十几条就到头了，没必要为它专门开批量口子。
  Future<void> _deleteSelected() async {
    final ids = _sel.toList();
    if (ids.isEmpty) return;
    setState(() => _sending = true);
    var ok = 0;
    for (final id in ids) {
      try {
        await Api.post('/dm/msg/$id/del', const {});
        ok++;
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _msgs.removeWhere((e) => ids.contains((e['id'] ?? 0) as int));
      _sel.clear();
      _multi = false;
      _sending = false;
    });
    if (ok < ids.length) toast(context, Lc.current.retry);
  }

  void _openPeer() {
    final name = (widget.peer['name'] ?? '') as String;
    if (name.isEmpty) return;
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => UserPage(name: name)));
  }

  void _openMe() {
    final name = (AppState.instance.user?['name'] ?? '') as String;
    if (name.isEmpty) return;
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => UserPage(name: name)));
  }

  void _insertEmoji(String e) {
    final sel = _input.selection;
    final text = _input.text;
    if (sel.isValid) {
      final at = sel.start;
      final end = sel.end < 0 ? at : sel.end;
      _input.text = text.replaceRange(at, end, e);
      _input.selection = TextSelection.collapsed(offset: at + e.length);
    } else {
      _input.text = text + e;
      _input.selection = TextSelection.collapsed(offset: _input.text.length);
    }
    setState(() {});
    _saveDraftSoon();
  }

  // ── 界面 ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: _multi ? _multiBar(cs) : _normalBar(cs),
      body: Column(
        children: [
          Expanded(
            child: PageWidth(
              max: 900,
              child: Stack(
                children: [
                  _msgArea(cs),
                  if (_loading)
                    const Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: LinearProgressIndicator(minHeight: 2),
                    ),
                  if (!_atBottom) _scrollButton(cs),
                ],
              ),
            ),
          ),
          PageWidth(max: 900, child: _composerArea(cs)),
        ],
      ),
    );
  }

  AppBar _normalBar(ColorScheme cs) {
    return AppBar(
      titleSpacing: 0,
      title: InkWell(
        onTap: _openPeer,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatarImg(
                url: _peerAvatar,
                name: _peerName,
                radius: 16,
                hue: _peerHue,
              ),
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
      actions: [
        IconButton(
          tooltip: Lc.current.search,
          icon: const Icon(Icons.search),
          onPressed: _openSearch,
        ),
      ],
    );
  }

  AppBar _multiBar(ColorScheme cs) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        tooltip: Lc.current.cancel,
        onPressed: _exitMulti,
      ),
      title: Text(Lc.current.dmSelectCount(_sel.length)),
      actions: [
        IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: Lc.current.delete,
          onPressed: _sel.isEmpty ? null : _deleteSelected,
        ),
      ],
    );
  }

  Widget _scrollButton(ColorScheme cs) {
    final n = _newCount;
    return Positioned(
      right: 14,
      bottom: 12,
      child: Material(
        color: n > 0 ? cs.primaryContainer : cs.surfaceContainerHighest,
        shape: const StadiumBorder(),
        elevation: 3,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => _toBottom(animate: true),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: n > 0 ? 14 : 10,
              vertical: 9,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (n > 0) ...[
                  Text(
                    Lc.current.dmNewBelow(n),
                    style: TextStyle(
                      fontSize: 12.5,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Icon(
                  Icons.keyboard_arrow_down,
                  size: 18,
                  color: n > 0 ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _msgArea(ColorScheme cs) {
    // 载入时这块留白，不要把转圈摆在中间——等下内容一出来，
    // 眼睛会觉得整块东西被人推了一下。进度看上面那条细线。
    if (_loading) return const SizedBox.expand();
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
    // 点消息区任意空白、或者人手开始往上翻，都收键盘。
    //
    // 只看 dragDetails：jumpTo/animateTo 自己贴底也会发 ScrollStartNotification
    // （dragDetails 是 null），跟着收的话，键盘一弹起来 didChangeMetrics 就贴底、
    // 贴底就收键盘，人就再也点不出键盘了。手指拖动、甩动才带 dragDetails。
    return NotificationListener<ScrollStartNotification>(
      onNotification: (n) {
        if (n.dragDetails != null) FocusScope.of(context).unfocus();
        return false;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        // reverse：列表从底部开始排。开页面第一帧就在最新一条上，
        // 没有「先画顶部、再跳到底」那一帧；往上翻历史、上面的图晚一步
        // 加载出来，也都不会推动眼前的内容。垫底的 SizedBox 是给
        // 「正在加载更早」那个小圈留的位置。
        child: ListView.builder(
          controller: _scroll,
          reverse: true,
          // 内容不满一屏也能拖，拖到边上有回弹，跟 QQ 微信一个手感
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          itemCount: _msgs.length + 1,
          itemBuilder: (context, i) {
            if (i == _msgs.length) {
              return SizedBox(
                height: 30,
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
            final idx = _msgs.length - 1 - i;
            final w = _row(cs, idx);
            final id = (_msgs[idx]['id'] ?? 0) as int;
            if (_unreadFromId <= 0 || id != _unreadFromId) return w;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [_unreadLine(cs), w],
            );
          },
        ),
      ),
    );
  }

  /// 「以下是新消息」——一条细线，别做成一块横幅，聊天页面经不起这么重的元素。
  Widget _unreadLine(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 2),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              color: cs.primary.withValues(alpha: 0.35),
              thickness: 1,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              Lc.current.newMessagesBelow,
              style: TextStyle(fontSize: 11.5, color: cs.primary),
            ),
          ),
          Expanded(
            child: Divider(
              color: cs.primary.withValues(alpha: 0.35),
              thickness: 1,
            ),
          ),
        ],
      ),
    );
  }

  bool _sameDay(int a, int b) {
    final da = DateTime.fromMillisecondsSinceEpoch(a * 1000);
    final db = DateTime.fromMillisecondsSinceEpoch(b * 1000);
    return da.year == db.year && da.month == db.month && da.day == db.day;
  }

  /// 日期分隔：今天、昨天，再往前写日期。
  Widget _dayPill(ColorScheme cs, int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    final now = DateTime.now();
    final diff = DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(d.year, d.month, d.day)).inDays;
    final label = diff == 0
        ? Lc.current.today
        : diff == 1
        ? Lc.current.yesterday
        : (d.year == now.year
              ? '${d.month}月${d.day}日'
              : '${d.year}年${d.month}月${d.day}日');
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 16, bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            color: cs.onSurfaceVariant,
            height: 1.2,
          ),
        ),
      ),
    );
  }

  Widget _row(ColorScheme cs, int idx) {
    final m = _msgs[idx];
    final ts = (m['created_at'] ?? 0) as int;
    final prev = idx > 0 ? _msgs[idx - 1] : null;
    final pts = prev == null ? 0 : (prev['created_at'] ?? 0) as int;
    final newDay = prev == null || !_sameDay(pts, ts);
    final showTime = newDay || (ts - pts).abs() >= 300;
    final mine = (m['from_id'] ?? 0) == _myId;
    final recalled = m['recalled'] == true;
    final tight = prev != null && (ts - pts).abs() < 300 && !newDay;
    final id = (m['id'] ?? 0) as int;

    // 自己发的最后一条、对方已经读了，底下标一个「已读」
    final lastMine =
        !recalled &&
        mine &&
        _msgs.skip(idx + 1).every((e) => (e['from_id'] ?? 0) != _myId);
    final read = lastMine && m['is_read'] == true;

    if (recalled) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (newDay) _dayPill(cs, ts),
          if (showTime && !newDay) _timePill(cs, ts),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Center(
              // 一条灰字太素，看着像渲染失败。给个淡底，明暗主题都认得出来。
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Text(
                  mine ? Lc.current.dmRecalledMine : Lc.current.dmRecalledPeer,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: cs.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    final body = (m['body'] ?? '') as String;
    final imgs = (m['images'] as List? ?? const []).cast<String>();
    final files = PostFile.listOf(m['files']);
    final reply = (m['reply'] as Map?)?.cast<String, dynamic>();
    final selected = _sel.contains(id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (newDay) _dayPill(cs, ts),
        if (showTime && !newDay) _timePill(cs, ts),
        Padding(
          padding: EdgeInsets.only(top: tight ? 5 : 14, left: 2, right: 2),
          // 长按弹菜单；点右边空白也管用，别只认气泡那小块
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPress: _multi ? null : () => _msgMenu(m),
            onTap: _multi ? () => _toggleSel(id) : null,
            child: Row(
              mainAxisAlignment: mine
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!mine) ...[
                  _avatar(_peerAvatar, _peerName, _openPeer, _peerHue),
                  const SizedBox(width: 7.5),
                ],
                if (_multi && !mine) _check(cs, selected),
                Flexible(
                  child: Column(
                    crossAxisAlignment: mine
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      _bubble(
                        cs,
                        mine,
                        body,
                        imgs,
                        files,
                        reply,
                        id: id,
                        selected: selected,
                      ),
                      if (read)
                        Padding(
                          padding: const EdgeInsets.only(top: 3, right: 4),
                          child: Text(
                            Lc.current.dmRead,
                            style: TextStyle(
                              fontSize: 10.5,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (_multi && mine) _check(cs, selected),
                if (mine) ...[
                  const SizedBox(width: 7.5),
                  _avatar(_myAvatar, _myName, _openMe, _myHue),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _check(ColorScheme cs, bool on) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
      child: Icon(
        on ? Icons.check_circle : Icons.radio_button_unchecked,
        size: 21,
        color: on ? cs.primary : cs.outline,
      ),
    );
  }

  Widget _avatar(String url, String name, VoidCallback onTap, double hue) {
    return GestureDetector(
      onTap: onTap,
      child: CircleAvatarImg(url: url, name: name, radius: 18, hue: hue),
    );
  }

  Widget _bubble(
    ColorScheme cs,
    bool mine,
    String body,
    List<String> imgs,
    List<PostFile> files,
    Map<String, dynamic>? reply, {
    int id = 0,
    bool selected = false,
  }) {
    // 谁发的就用谁的颜色：自己实色，对方同色系浅底
    final dark = Theme.of(context).brightness == Brightness.dark;
    final hue = mine ? _myHue : _peerHue;
    final bg = mine ? bubbleMineBg(hue, dark) : bubblePeerBg(hue, dark);
    final fg = mine ? bubbleMineFg(hue) : bubblePeerFg(hue, dark);
    final onlyImgs =
        body.isEmpty && imgs.isNotEmpty && files.isEmpty && reply == null;
    final maxW = MediaQuery.of(context).size.width * _bubbleRatio;

    final bubble = ConstrainedBox(
      // 长按菜单靠它算位置，一条气泡一个 key。
      key: _bubbleKeys.putIfAbsent(id, () => GlobalKey()),
      constraints: BoxConstraints(maxWidth: maxW < 420 ? maxW : 420),
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          // 靠头像那只角小圆角，其余三个大圆角——不画尖角，尖角配小圆角显脏
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(mine ? 18 : 6),
            bottomRight: Radius.circular(mine ? 6 : 18),
          ),
          border: selected
              ? Border.all(color: cs.tertiary, width: 2)
              : (dark && !mine
                    ? Border.all(color: bubbleEdge(hue, dark))
                    : null),
        ),
        padding: EdgeInsets.all(onlyImgs ? 3 : 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (reply != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 1, 6, 0),
                child: _quoteBlock(fg, reply),
              ),
            if (imgs.isNotEmpty) _images(imgs, id),
            if (files.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(3, 3, 3, 0),
                child: FileCards(files: files, compact: true),
              ),
            if (body.isNotEmpty)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  9,
                  (imgs.isEmpty && files.isEmpty) ? 2 : 7,
                  9,
                  3,
                ),
                child: Text(
                  body,
                  style: TextStyle(fontSize: 15.5, height: 1.42, color: fg),
                ),
              ),
          ],
        ),
      ),
    );
    // 按住时压一点，跟微信的手感。
    return AnimatedScale(
      scale: _pressedId == id ? 0.96 : 1,
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOut,
      child: bubble,
    );
  }

  /// 气泡顶上那小块引用。不带竖线，靠底色和浅字区分，省得深色模式下糊成一片。
  Widget _quoteBlock(Color tint, Map<String, dynamic> r) {
    final name = (r['name'] ?? '') as String;
    final body = (r['body'] ?? '') as String;
    final hasImg = r['has_img'] == true;
    final summary = body.isNotEmpty
        ? body
        : (hasImg ? Lc.current.replyImage : '');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (name.isNotEmpty)
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: tint.withValues(alpha: 0.75),
              ),
            ),
          Text(
            summary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: tint.withValues(alpha: 0.9)),
          ),
        ],
      ),
    );
  }

  /// 网络图片，按显示尺寸解码。
  ///
  /// 以前直接 Image.network 原图，一张照片四五兆，九张一起就是几十兆，
  /// 解到内存里还按原始尺寸铺开——聊到一个带图的消息就卡一下。
  /// 缩略图按 3 倍像素密度要就够清楚了。
  /// 聊天气泡里的方图。走磁盘缓存，失败能点一下重来——
  /// 原来用 Image.network，网络一抖就是一张破图，点它也没反应。
  Widget _netImg(
    String url,
    double side, {
    double radius = 9,
    BoxFit fit = BoxFit.cover,
  }) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final px = (side * dpr).round();
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: side,
        height: side,
        child: RetryImage(
          url: Api.img(url),
          fit: fit,
          memCacheWidth: px,
          probeSize: false,
        ),
      ),
    );
  }

  /// 图片排版：一张放大，四张以上走三列九宫格。
  Widget _images(List<String> imgs, int id) {
    final one = imgs.length == 1;
    final side = one ? 200.0 : 104.0;
    void tap(int i) {
      if (_multi) {
        _toggleSel(id);
      } else {
        _viewImage(imgs, i);
      }
    }

    if (one) {
      return GestureDetector(
        onTap: () => tap(0),
        child: _netImg(imgs[0], side, radius: 13),
      );
    }
    return SizedBox(
      width: side * 3 + 8,
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (var i = 0; i < imgs.length; i++)
            GestureDetector(onTap: () => tap(i), child: _netImg(imgs[i], side)),
        ],
      ),
    );
  }

  /// 跟帖子里点图走同一个查看器，缩放、翻页、存图都是那一套。
  void _viewImage(List<String> urls, int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ImageViewerPage(urls: urls, initial: index),
      ),
    );
  }

  Widget _timePill(ColorScheme cs, int ts) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(
          _fmtTime(ts),
          style: TextStyle(
            fontSize: 11,
            color: cs.onSurfaceVariant.withValues(alpha: 0.85),
            height: 1.2,
          ),
        ),
      ),
    );
  }

  /// 同一天只给时分。日期由分隔条负责，这里不再重复。
  String _fmtTime(int ts) {
    if (ts <= 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  // ── 输入区 ────────────────────────────────────────────

  Widget _composerArea(ColorScheme cs) {
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

    final hasContent =
        _input.text.trim().isNotEmpty ||
        _pending.isNotEmpty ||
        _pendingFiles.isNotEmpty;
    final canSend = hasContent && !_sending;
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
            if (_failedWhy.isNotEmpty) _failedBar(cs),
            if (_replyTo != null) _replyBar(cs),
            if (_pending.isNotEmpty || _pendingFiles.isNotEmpty)
              _pendingBar(cs),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 8, 6),
              child: _inputRow(cs, canSend),
            ),
            if (_showEmoji) _emojiPanel(cs),
          ],
        ),
      ),
    );
  }

  /// 没发出去的那一条。点重试就再来，点 × 扔掉。
  /// 不弹个 toast 就完：那条提示 1.5 秒后消失，人回头就不知道啥没发出去。
  Widget _failedBar(ColorScheme cs) {
    return Container(
      color: cs.errorContainer.withValues(alpha: 0.6),
      padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 16, color: cs.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _failedWhy,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: cs.onErrorContainer),
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            onPressed: _sending ? null : _send,
            child: Text(
              Lc.current.retry,
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: _dropFailed,
            tooltip: Lc.current.cancel,
            icon: Icon(Icons.close, size: 16, color: cs.onErrorContainer),
          ),
        ],
      ),
    );
  }

  Widget _replyBar(ColorScheme cs) {
    final r = _replyTo!;
    final body = (r['body'] ?? '') as String;
    final hasImg =
        (r['images'] as List? ?? const []).isNotEmpty ||
        (r['files'] as List? ?? const []).isNotEmpty;
    final mine = (r['from_id'] ?? 0) == _myId;
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
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  _pending[i],
                  width: 60,
                  height: 60,
                  fit: BoxFit.cover,
                ),
              ),
              Positioned(
                top: -6,
                right: -6,
                child: GestureDetector(
                  onTap: () => setState(() => _pending.removeAt(i)),
                  child: Container(
                    padding: const EdgeInsets.all(1),
                    decoration: BoxDecoration(
                      color: cs.surface,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.cancel, size: 16),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _fileTile(ColorScheme cs, PostFile f, VoidCallback onRemove) {
    return SizedBox(
      width: 168,
      height: 60,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 168,
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.insert_drive_file, size: 22, color: cs.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        f.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                      Text(
                        bytesText(f.size),
                        style: TextStyle(
                          fontSize: 10,
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
            top: -6,
            right: -6,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(1),
                decoration: BoxDecoration(
                  color: cs.surface,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.cancel, size: 16),
              ),
            ),
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
          onPressed: () {
            // 开表情面板就收键盘；从面板切回键盘得把焦点要回来，
            // 光把面板藏掉系统不会自己弹键盘，看着就是点不出键盘。
            setState(() => _showEmoji = !_showEmoji);
            if (_showEmoji) {
              FocusScope.of(context).unfocus();
            } else {
              _focus.requestFocus();
            }
          },
          tooltip: Lc.current.dmEmoji,
          visualDensity: VisualDensity.compact,
          icon: Icon(
            _showEmoji
                ? Icons.keyboard_outlined
                : Icons.emoji_emotions_outlined,
            size: 25,
            color: cs.onSurfaceVariant,
          ),
        ),
        Expanded(
          child: Container(
            constraints: const BoxConstraints(minHeight: 42),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(21),
            ),
            child: TextField(
              controller: _input,
              focusNode: _focus,
              minLines: 1,
              maxLines: 5,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              onChanged: (_) {
                setState(() {});
                _saveDraftSoon();
              },
              style: const TextStyle(fontSize: 15, height: 1.3),
              decoration: const InputDecoration(
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
        IconButton(
          onPressed: _sending ? null : _attachMenu,
          tooltip: Lc.current.addImage,
          visualDensity: VisualDensity.compact,
          icon: _compressing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add_circle_outline, size: 25),
        ),
        SizedBox(
          height: 40,
          child: canSend
              ? FilledButton(
                  onPressed: _send,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    minimumSize: const Size(0, 40),
                    visualDensity: VisualDensity.compact,
                    shape: const StadiumBorder(),
                  ),
                  child: _sending
                      ? (_sendTotal > 1
                            // 九张图一张张传，没个数看着就像卡死了
                            ? Text(
                                '$_sendAt/$_sendTotal',
                                style: const TextStyle(fontSize: 13),
                              )
                            : const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ))
                      : Text(
                          Lc.current.send,
                          style: const TextStyle(fontSize: 14),
                        ),
                )
              : IconButton(
                  onPressed: null,
                  icon: const Icon(Icons.send, size: 22),
                  tooltip: Lc.current.send,
                ),
        ),
      ],
    );
  }

  /// 表情面板。常用的一屏够了，不做分组，也不做贴纸。
  Widget _emojiPanel(ColorScheme cs) {
    const faces = [
      '😀',
      '😄',
      '😁',
      '😆',
      '😅',
      '😂',
      '🙂',
      '😊',
      '😉',
      '😍',
      '🥰',
      '😘',
      '😜',
      '🤪',
      '🤔',
      '🤨',
      '😐',
      '😑',
      '😴',
      '😪',
      '😔',
      '😢',
      '😭',
      '😤',
      '😠',
      '🤯',
      '🥵',
      '🥶',
      '😱',
      '🤗',
      '🤫',
      '🙄',
      '😮',
      '😲',
      '🥺',
      '😎',
      '🤓',
      '👍',
      '👎',
      '👌',
      '✌️',
      '🤝',
      '🙏',
      '👏',
      '💪',
      '❤️',
      '💔',
      '🎉',
    ];
    return Container(
      height: 208,
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: cs.outlineVariant.withValues(alpha: 0.5),
            width: 0.5,
          ),
        ),
      ),
      child: GridView.count(
        crossAxisCount: 8,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        children: [
          for (final e in faces)
            InkWell(
              onTap: () => _insertEmoji(e),
              borderRadius: BorderRadius.circular(8),
              child: Center(
                child: Text(e, style: const TextStyle(fontSize: 22)),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openSearch() async {
    await showAppSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.82,
        child: _ChatSearchSheet(
          peerId: _peerId,
          myId: _myId,
          peerName: _peerName,
          myName: _myName,
          onQuote: (m) {
            Navigator.pop(ctx);
            setState(() => _replyTo = m);
            _focus.requestFocus();
          },
        ),
      ),
    );
  }
}

/// 会话内搜索。服务端 LIKE 查，最多 30 条，点一下复制、或者引用回输入栏。
class _ChatSearchSheet extends StatefulWidget {
  const _ChatSearchSheet({
    required this.peerId,
    required this.myId,
    required this.peerName,
    required this.myName,
    required this.onQuote,
  });

  final int peerId;
  final int myId;
  final String peerName;
  final String myName;
  final void Function(Map<String, dynamic> m) onQuote;

  @override
  State<_ChatSearchSheet> createState() => _ChatSearchSheetState();
}

class _ChatSearchSheetState extends State<_ChatSearchSheet> {
  final TextEditingController _q = TextEditingController();
  List<Map<String, dynamic>> _res = const [];
  bool _busy = false;
  bool _searched = false;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _run(v));
  }

  Future<void> _run(String v) async {
    final kw = v.trim();
    if (kw.isEmpty) {
      setState(() {
        _res = const [];
        _searched = false;
      });
      return;
    }
    setState(() => _busy = true);
    try {
      final d = await Api.get('/dm/${widget.peerId}/search', query: {'q': kw});
      if (!mounted) return;
      setState(() {
        _res = (d['items'] as List).cast<Map<String, dynamic>>();
        _busy = false;
        _searched = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _searched = true;
      });
    }
  }

  String _when(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _q,
              autofocus: true,
              onChanged: _onChanged,
              onSubmitted: _run,
              decoration: InputDecoration(
                hintText: Lc.current.dmSearchHint,
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                filled: true,
                fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.7),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          Expanded(child: _body(cs)),
        ],
      ),
    );
  }

  Widget _body(ColorScheme cs) {
    if (!_searched) {
      return Center(
        child: Text(
          Lc.current.dmSearchHint,
          style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
        ),
      );
    }
    if (_res.isEmpty) {
      return Center(
        child: Text(
          Lc.current.dmSearchEmpty,
          style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: _res.length,
      separatorBuilder: (_, i) =>
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.4)),
      itemBuilder: (context, i) {
        final m = _res[i];
        final mine = (m['from_id'] ?? 0) == widget.myId;
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          title: Text(
            (m['body'] ?? '') as String,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14),
          ),
          subtitle: Text(
            '${mine ? widget.myName : widget.peerName} · '
            '${_when((m['created_at'] ?? 0) as int)}',
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.reply, size: 18),
            tooltip: Lc.current.quote,
            onPressed: () => widget.onQuote(m),
          ),
          onTap: () {
            Clipboard.setData(ClipboardData(text: '${m['body']}'));
            toast(context, Lc.current.copied);
          },
        );
      },
    );
  }
}

/// 长按菜单里的一项。
class _MsgAction {
  const _MsgAction(this.icon, this.label, this.run);

  final IconData icon;
  final String label;
  final VoidCallback run;
}

/// 工具条的底：圆角矩形加一个指向气泡的小三角，两者合成一条 path，
/// 阴影才不会在接缝处断开。
class _MsgMenuPainter extends CustomPainter {
  _MsgMenuPainter({
    required this.bg,
    required this.above,
    required this.arrowX,
    required this.barH,
    required this.arrowH,
  });

  final Color bg;

  /// true = 条子在气泡上方，三角朝下；false = 在下方，三角朝上。
  final bool above;
  final double arrowX;
  final double barH;
  final double arrowH;

  @override
  void paint(Canvas canvas, Size size) {
    final bar = Rect.fromLTWH(0, above ? 0 : arrowH, size.width, barH);
    final body = Path()
      ..addRRect(RRect.fromRectAndRadius(bar, const Radius.circular(9)));

    const half = 6.5;
    final tip = above ? bar.bottom + arrowH : bar.top - arrowH;
    final tri = Path()
      ..moveTo(arrowX - half, above ? bar.bottom - 0.5 : bar.top + 0.5)
      ..lineTo(arrowX + half, above ? bar.bottom - 0.5 : bar.top + 0.5)
      ..lineTo(arrowX, tip);

    final path = Path.combine(PathOperation.union, body, tri);
    canvas.drawShadow(path, Colors.black, 6, false);
    canvas.drawPath(path, Paint()..color = bg);
  }

  @override
  bool shouldRepaint(_MsgMenuPainter old) =>
      old.bg != bg ||
      old.above != above ||
      old.arrowX != arrowX ||
      old.barH != barH ||
      old.arrowH != arrowH;
}
