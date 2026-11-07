import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../api.dart';
import '../file_pick.dart';
import '../plat.dart';
import '../widgets/app_card.dart';
import '../widgets/app_sheet.dart';
import '../widgets/page_width.dart';
import '../widgets/mention.dart';
import '../haptics.dart';
import '../read_pos.dart';
import '../store.dart';
import '../user_hue.dart';
import '../img_compress.dart';
import 'gallery_picker_page.dart';
import 'edit_thread_page.dart';
import '../utils.dart';
import '../widgets/avatar.dart';
import '../widgets/name_tag.dart';
import '../widgets/file_card.dart';
import '../widgets/post_images.dart';
import '../widgets/skeleton.dart';
import '../widgets/user_link.dart';

import '../l10n/error_text.dart';
import '../share_out.dart';
import '../l10n/l10n.dart';
import '../widgets/toast.dart';

/// 帖子详情：楼层 + 楼中楼。
class ThreadPage extends StatefulWidget {
  final int threadId;
  final String title;

  /// 从通知进来时带楼层 id，加载完自动滚过去。
  final int? focusPostId;

  /// 宽屏时嵌在列表右边，不占一整条路由：不显示返回箭头，
  /// 关掉它走 onClose，而不是 pop。
  final bool embedded;
  final VoidCallback? onClose;

  const ThreadPage({
    super.key,
    required this.threadId,
    required this.title,
    this.focusPostId,
    this.embedded = false,
    this.onClose,
  });

  @override
  State<ThreadPage> createState() => _ThreadPageState();
}

class _ThreadPageState extends State<ThreadPage> {
  final ItemScrollController _itemScroll = ItemScrollController();
  final ItemPositionsListener _posListener = ItemPositionsListener.create();
  final TextEditingController _input = TextEditingController();
  final MentionWatcher _mention = MentionWatcher();
  final FocusNode _inputFocus = FocusNode();

  Map<String, dynamic>? _thread;
  final List<Map<String, dynamic>> _posts = [];

  int _page = 1;
  int _pages = 1;
  bool _busy = false;
  bool _first = true;
  String? _err;
  bool _sending = false;

  /// 只看楼主
  bool _onlyAuthor = false;

  /// 上次构建出来给列表看的条数，翻页判断要用
  int _shownLen = 0;

  /// 刚跳过去的楼层，闪一下再恢复
  int _flashFloor = 0;

  /// 滑过两屏才浮出回顶按钮，一进来就挂个按钮在旁边太吵。
  bool _showTop = false;

  /// 翻页失败：有内容时只在底部提示重试，不拿顶部红条盖住正文。
  String? _moreErr;

  /// 滚动停下来再记位置，拖动过程中每帧写盘太浪费。
  Timer? _posTimer;

  int? _ownerId;

  /// 正在回复的楼层；null 表示回复楼主
  Map<String, dynamic>? _replyTo;

  final ImagePicker _picker = ImagePicker();
  final List<Uint8List> _imgs = [];
  final List<PostFile> _files = [];
  bool _compressing = false;

  @override
  void initState() {
    super.initState();
    _input.addListener(_onMention);
    // 资料可能在别处改过，进帖子页时对一次，底栏头像才不会停在旧的
    AppState.instance.refreshUser();
    _posListener.itemPositions.addListener(_onPositions);
    _boot();
  }

  void _onPositions() {
    final ps = _posListener.itemPositions.value;
    if (ps.isEmpty) return;
    var first = 1 << 30;
    var last = 0;
    for (final e in ps) {
      if (e.index < first) first = e.index;
      if (e.index > last) last = e.index;
    }
    // 提前量按这一屏摆得下几楼来算，滑到底时下一页已经在手上。
    final ahead = ps.length + 2;
    if (last >= _shownLen - ahead) _loadMore();

    // index 0 是一楼头部，滑过它两楼以上才给回顶
    final show = first > 2;
    if (show != _showTop) setState(() => _showTop = show);

    _posTimer?.cancel();
    _posTimer = Timer(const Duration(milliseconds: 700), _savePos);
  }

  /// 记下当前停在的那一层。失败不吭声，这东西坏了最多是下次从头看。
  Future<void> _savePos() async {
    if (_posts.isEmpty) return;
    final ps = _posListener.itemPositions.value;
    if (ps.isEmpty) return;
    // 取屏幕最上面那条完整可见的楼
    final vis = ps.where((e) => e.itemLeadingEdge < 0.9).toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    final idx = (vis.isEmpty ? ps.first.index : vis.first.index) - 1;
    final list = _shownList();
    if (idx < 0 || idx >= list.length) return;
    final p = list[idx];
    await ReadPos.put(
      widget.threadId,
      (p['id'] ?? 0) as int,
      ((p['floor'] ?? 0) as num).toInt(),
    );
  }

  /// 有 focusPostId 就先把目标页加载出来，再滚过去。
  /// 没有的话翻一下上次读到哪儿，接着看。
  Future<void> _boot() async {
    var fid = widget.focusPostId;
    if (fid == null) {
      final saved = await ReadPos.get(widget.threadId);
      fid = (saved?['id'] as num?)?.toInt();
      if (!mounted) return;
    }
    if (fid == null) {
      await _loadMore();
      return;
    }
    var target = 1;
    try {
      final d = await Api.get(
        '/t/${widget.threadId}',
        query: {'page': '1', 'post': '$fid'},
      );
      target = (d['focus_page'] ?? 1) as int;
    } on ApiException {
      // 定位失败就当普通打开
    }
    await _loadMore();
    var guard = 0;
    while (mounted && _page <= target && _page <= _pages && guard < 30) {
      await _loadMore();
      guard++;
    }
    await _jumpToFocus(fid);
  }

  /// 回顶。双击标题用，落到第 0 项。
  void _toTop() {
    if (!_itemScroll.isAttached) return;
    _itemScroll.scrollTo(
      index: 0,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _jumpToFocus(int fid) async {
    final idx = _posts.indexWhere((p) => p['id'] == fid);
    if (idx < 0 || !_itemScroll.isAttached) return;
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!mounted || !_itemScroll.isAttached) return;
    _itemScroll.scrollTo(
      index: idx + 1,
      alignment: 0.08,
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
    );
  }

  /// 输入楼层号，问服务端它在第几页，翻到再滚过去。
  Future<void> _jumpToFloor() async {
    final ctl = TextEditingController();
    final n = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Lc.current.jumpToFloor),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(hintText: Lc.current.floorJumpHint),
          onSubmitted: (v) => Navigator.of(ctx).pop(int.tryParse(v)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(Lc.current.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(int.tryParse(ctl.text)),
            child: Text(Lc.current.jump),
          ),
        ],
      ),
    );
    ctl.dispose();
    if (!mounted || n == null || n < 1) return;

    if (n == 1) {
      if (_itemScroll.isAttached) {
        _itemScroll.scrollTo(
          index: 0,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        );
      }
      return;
    }

    var target = 1;
    try {
      final d = await Api.get(
        '/t/${widget.threadId}',
        query: {'page': '1', 'floor': '$n'},
      );
      target = (d['focus_page'] ?? 1) as int;
    } on ApiException {
      // 服务端给不出页码就按已加载的范围找
    }
    if (!mounted) return;

    var guard = 0;
    while (mounted && _page <= target && _page <= _pages && guard < 60) {
      await _loadMore();
      guard++;
    }
    if (!mounted) return;

    // 只看楼主开着就看不到别人的楼层，先放开
    if (_onlyAuthor) setState(() => _onlyAuthor = false);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    if (!mounted) return;

    final list = _shownList();
    final idx = list.indexWhere((p) => (p['floor'] ?? 0) == n);
    if (idx < 0) {
      _toast(
        _page <= _pages
            ? Lc.current.notReachedFloor('$n')
            : Lc.current.noSuchFloor('$n'),
      );
      return;
    }
    if (!_itemScroll.isAttached) return;
    _itemScroll.scrollTo(
      index: idx + 1,
      alignment: 0.08,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
    setState(() => _flashFloor = n);
    Future<void>.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _flashFloor = 0);
    });
  }

  void _onMention() => _mention.scan(_input);

  @override
  void dispose() {
    _posTimer?.cancel();
    _input.removeListener(_onMention);
    _mention.dispose();
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  /// 右下角回顶。滑过两屏才浮出来，到头就缩回去。
  Widget _backTop(ColorScheme cs) {
    return AnimatedScale(
      scale: _showTop ? 1 : 0,
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      child: IgnorePointer(
        ignoring: !_showTop,
        child: Tooltip(
          message: Lc.current.backToTop,
          child: Material(
            color: cs.surfaceContainerHigh,
            elevation: 2,
            shadowColor: Colors.black26,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () {
                if (!_itemScroll.isAttached) return;
                _itemScroll.scrollTo(
                  index: 0,
                  duration: const Duration(milliseconds: 420),
                  curve: Curves.easeOutCubic,
                );
              },
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Icon(
                  Icons.vertical_align_top_rounded,
                  size: 20,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 翻页失败时挂在列表末尾：滑到底看得见，点一下重来。
  Widget _moreBar(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      child: Column(
        children: [
          Text(
            _moreErr ?? '',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: cs.outline),
          ),
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: _retryMore,
            icon: const Icon(Icons.refresh, size: 16),
            label: Text(Lc.current.retry),
          ),
        ],
      ),
    );
  }

  Future<void> _loadMore() async {
    if (_busy || _page > _pages) return;
    _busy = true;
    final before = _posts.length;
    try {
      final d = await Api.get(
        '/t/${widget.threadId}',
        query: {'page': '$_page'},
        cache: _page == 1,
      );
      final cached = Api.lastFromCache;
      if (!mounted) return;
      setState(() {
        _thread = d['thread'] as Map<String, dynamic>;
        _ownerId ??= _thread!['owner_id'] as int?;
        _posts.addAll((d['posts'] as List).cast<Map<String, dynamic>>());
        _pages = (d['pages'] ?? 1) as int;
        _page++;
        _first = false;
        _err = cached ? Lc.current.offlineCached : null;
        _moreErr = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      final msg = errorText(context, e);
      setState(() {
        _first = false;
        // 已经有内容就别拿红条盖住正文，底部给个重试就够
        if (_posts.isEmpty) {
          _err = msg;
        } else {
          _moreErr = msg;
        }
      });
    } finally {
      _busy = false;
    }
    // 只看楼主：这一页全是别人回的，就接着往下拉，别让列表看着空
    final gotOp = _posts.skip(before).any((p) => p['author_id'] == _ownerId);
    if (mounted && _onlyAuthor && !gotOp && _page <= _pages && _err == null) {
      await _loadMore();
    }
  }

  /// 一楼并进头部，剩下的按需过滤
  List<Map<String, dynamic>> _shownList() {
    final opIdx = _posts.indexWhere((p) => (p['floor'] ?? 0) == 1);
    final rest = opIdx >= 0
        ? <Map<String, dynamic>>[
            ..._posts.sublist(0, opIdx),
            ..._posts.sublist(opIdx + 1),
          ]
        : <Map<String, dynamic>>[..._posts];
    if (!_onlyAuthor) return rest;
    return rest.where((p) => p['author_id'] == _ownerId).toList();
  }

  Future<void> _reload() async {
    setState(() {
      _posts.clear();
      _page = 1;
      _pages = 1;
      _first = true;
      _err = null;
      _moreErr = null;
    });
    await _loadMore();
  }

  /// 下拉刷新：只换掉第一页，后面已经翻出来的楼层留着。
  ///
  /// 不用 [_reload]——那会把整页清成骨架屏，下拉一下屏幕闪白，
  /// 而且已经读到第 20 页的人会被拽回第 1 页。
  Future<void> _pullRefresh() async {
    final before = _posts.isEmpty
        ? 0
        : ((_posts.last['floor'] ?? 0) as num).toInt();
    try {
      final d = await Api.get(
        '/t/${widget.threadId}',
        query: {'page': '1'},
        cache: true,
      );
      if (!mounted) return;
      final head = (d['posts'] as List).cast<Map<String, dynamic>>();
      final headLast = head.isEmpty
          ? 0
          : ((head.last['floor'] ?? 0) as num).toInt();
      setState(() {
        _thread = (d['thread'] as Map<String, dynamic>?) ?? _thread;
        _ownerId ??= _thread!['owner_id'] as int?;
        // 第一页覆盖到的楼层整段换新，后面的原样接上
        final tail = _posts
            .where((p) => ((p['floor'] ?? 0) as num).toInt() > headLast)
            .toList();
        _posts
          ..clear()
          ..addAll(head)
          ..addAll(tail);
        final np = ((d['pages'] ?? _pages) as num).toInt();
        _pages = np;
        if (_page > np) _page = np;
        _err = Api.lastFromCache ? Lc.current.offlineCached : null;
        _moreErr = null;
      });
      final added = headLast - before;
      if (added > 0) _toast(Lc.current.newRepliesN('$added'));
    } on ApiException catch (e) {
      if (!mounted) return;
      _toast(errorText(context, e));
    }
  }

  Future<void> _retryMore() async {
    setState(() => _moreErr = null);
    await _loadMore();
  }

  /// 发完回复只补最后一页，别把人从第 20 页踢回第 1 页。
  Future<void> _refreshTail() async {
    if (_page <= _pages || _pages < 1) {
      await _reload();
      return;
    }
    try {
      final d = await Api.get(
        '/t/${widget.threadId}',
        query: {'page': '$_pages'},
      );
      if (!mounted) return;
      final last = (d['posts'] as List).cast<Map<String, dynamic>>();
      if (last.isEmpty) return;
      final from = ((last.first['floor'] ?? 0) as num).toInt();
      setState(() {
        _thread = (d['thread'] as Map<String, dynamic>?) ?? _thread;
        _posts.removeWhere((p) => ((p['floor'] ?? 0) as num).toInt() >= from);
        _posts.addAll(last);
        final np = ((d['pages'] ?? _pages) as num).toInt();
        _pages = np;
        _page = np + 1;
      });
    } on ApiException {
      // 补不上就维持原样，不把列表清空
    }
  }

  Future<void> _send() async {
    if (!AppState.instance.loggedIn) {
      _toast(Lc.current.needLogin);
      return;
    }
    final body = _input.text.trim();
    if ((body.isEmpty && _imgs.isEmpty && _files.isEmpty) || _sending) return;
    setState(() => _sending = true);
    try {
      final urls = <String>[];
      for (final b in _imgs) {
        urls.add(await Api.uploadImage(b));
      }
      await Api.post('/t/${widget.threadId}/reply', {
        'body': body,
        'parent_id': _replyTo?['id'],
        'images': urls,
        'files': _files.map((f) => f.toJson()).toList(),
      });
      _input.clear();
      if (mounted) {
        setState(() {
          _replyTo = null;
          _sending = false;
          _imgs.clear();
          _files.clear();
        });
      }
      await _refreshTail();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      _toast(e);
    }
  }

  /// 传 String 直接显示，传异常就按当前语言翻译。
  /// context 留在方法里用，别让调用点在 await 之后碰它。
  void _toast(Object s) {
    if (!mounted) return;
    final t = s is String ? s : errorText(context, s);
    toast(context, t);
  }

  /// 嵌入模式下没有路由可退，交给外面关掉；整页模式照旧 pop。
  void _close([bool? result]) {
    if (widget.embedded) {
      widget.onClose?.call();
    } else {
      Navigator.of(context).pop(result);
    }
  }

  void _beginReply(Map<String, dynamic> post) {
    if (!AppState.instance.loggedIn) {
      _toast(Lc.current.needLogin);
      return;
    }
    setState(() => _replyTo = post);
    _inputFocus.requestFocus();
  }

  /// 管理员置顶 / 加精，状态用后端返回的为准。
  Future<void> _adminToggle(String kind) async {
    final t = _thread;
    if (t == null) return;
    try {
      final r = await Api.post('/admin/t/${t['id']}/$kind', const {});
      final on = r[kind == 'top' ? 'is_top' : 'is_good'] == true;
      setState(() {
        _thread = {...t, if (kind == 'top') 'is_top': on else 'is_good': on};
      });
      _toast(
        kind == 'top'
            ? (on ? Lc.current.pinnedToast : Lc.current.unpinnedToast)
            : (on ? Lc.current.featuredToast : Lc.current.unfeaturedToast),
      );
    } on ApiException catch (e) {
      _toast(e);
    }
  }

  /// 选个举报理由，取消返回 null。
  Future<String?> _pickReason() {
    return showAppSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  Lc.current.reportReason,
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
            for (final r in [
              Lc.current.reportSpam,
              Lc.current.reportAbuse,
              Lc.current.reportIllegal,
              Lc.current.reportFalse,
              Lc.current.reportOther,
            ])
              ListTile(title: Text(r), onTap: () => Navigator.of(ctx).pop(r)),
          ],
        ),
      ),
    );
  }

  Future<void> _sendReport(Map<String, dynamic> body) async {
    try {
      final r = await Api.post('/report', body);
      _toast(
        r['duplicate'] == true
            ? Lc.current.reportDuplicate
            : Lc.current.reportThanks,
      );
    } on ApiException catch (e) {
      _toast(e);
    }
  }

  /// 举报整帖。
  /// 走系统分享面板，把帖子的标题和开头几行发出去。
  /// 网页版没有深链，所以带上站点地址让对方自己找。
  Future<void> _shareThread() async {
    final t = _thread;
    if (t == null) return;
    final op = _posts.isEmpty ? const <String, dynamic>{} : _posts.first;
    final body = ((op['body'] ?? '') as String).trim();
    final excerpt = body.length > 160 ? '${body.substring(0, 160)}…' : body;
    final who = (op['author'] ?? '') as String;
    final text = [
      '【${widget.title}】',
      if (excerpt.isNotEmpty) excerpt,
      '——${who.isEmpty ? '' : '$who · '}${Api.base}',
    ].join('\n');
    final ok = await shareText(text, subject: widget.title);
    if (ok) return;
    // 分享面板拉不起来（桌面没装、浏览器不支持），退回复制。
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) _toast(Lc.current.copied);
  }

  Future<void> _reportThread() async {
    final t = _thread;
    if (t == null) return;
    if (!AppState.instance.loggedIn) {
      _toast(Lc.current.needLogin);
      return;
    }
    final reason = await _pickReason();
    if (reason == null) return;
    await _sendReport({'thread_id': t['id'], 'reason': reason});
  }

  /// 举报某一层。
  Future<void> _reportReply(Map<String, dynamic> post) async {
    if (!AppState.instance.loggedIn) {
      _toast(Lc.current.needLogin);
      return;
    }
    final reason = await _pickReason();
    if (reason == null) return;
    await _sendReport({'reply_id': post['id'], 'reason': reason});
  }

  Future<bool> _confirmDelete(String title, String note) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(note),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(Lc.current.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(Lc.current.delete),
          ),
        ],
      ),
    );
    return ok == true;
  }

  /// 改自己的帖子。图片在编辑页里增删，这里只负责把结果拿回来。
  Future<void> _editThread() async {
    if (!AppState.instance.loggedIn) {
      _toast(Lc.current.needLogin);
      return;
    }
    final t = _thread;
    if (t == null) return;
    Map<String, dynamic> op = const {};
    for (final p in _posts) {
      if ((p['floor'] ?? 0) == 1) {
        op = p;
        break;
      }
    }
    final imgs = ((op['images'] as List?) ?? const []).cast<String>();
    final files = PostFile.listOf(op['files']);
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EditThreadPage(
          tid: widget.threadId,
          title: (t['title'] ?? widget.title) as String,
          body: (op['body'] ?? '') as String,
          images: imgs,
          files: files,
        ),
      ),
    );
    if (changed == true && mounted) {
      _toast(Lc.current.changed);
      await _reload();
    }
  }

  /// 改回复：只动正文，配图原样留着。
  Future<void> _editReply(Map<String, dynamic> post) async {
    if (!AppState.instance.loggedIn) {
      _toast(Lc.current.needLogin);
      return;
    }
    final id = (post['id'] ?? 0) as int;
    final ctrl = TextEditingController(text: (post['body'] ?? '') as String);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Lc.current.editFloor),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          minLines: 3,
          maxLines: 8,
          maxLength: 20000,
          decoration: InputDecoration(hintText: Lc.current.saySomething),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(Lc.current.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(Lc.current.save),
          ),
        ],
      ),
    );
    if (ok != true) {
      ctrl.dispose();
      return;
    }
    final body = ctrl.text.trim();
    ctrl.dispose();
    try {
      await Api.patch('/c/$id', {'body': body});
      if (!mounted) return;
      _toast(Lc.current.changed);
      await _reload();
    } on ApiException catch (e) {
      _toast(e);
    }
  }

  /// 管理员：把这一帖（含回复）里的图全换成占位图。
  Future<void> _wipeImages() async {
    final ok = await _confirmDelete(
      Lc.current.replaceWithPlaceholder,
      Lc.current.replacePlaceholderConfirm,
    );
    if (!ok) return;
    try {
      final d = await Api.post('/t/${widget.threadId}/replace-images', {});
      if (!mounted) return;
      _toast(Lc.current.replacedImages('${d['changed'] ?? 0}'));
      _reload();
    } on ApiException catch (e) {
      _toast(e);
    }
  }

  Future<void> _deleteThread() async {
    if (!AppState.instance.loggedIn) {
      _toast(Lc.current.needLogin);
      return;
    }
    final ok = await _confirmDelete(
      Lc.current.deletePostConfirm,
      Lc.current.deleteThreadConfirm,
    );
    if (!ok) return;
    try {
      await Api.delete('/t/${widget.threadId}');
      if (!mounted) return;
      await ReadPos.clear(widget.threadId);
      if (!mounted) return;
      _toast(Lc.current.postDeleted);
      _close(true);
    } on ApiException catch (e) {
      _toast(e);
    }
  }

  Future<void> _deletePost(Map<String, dynamic> post) async {
    if (!AppState.instance.loggedIn) {
      _toast(Lc.current.needLogin);
      return;
    }
    final id = (post['id'] ?? 0) as int;
    final isThread = (post['floor'] ?? 0) == 1;
    final ok = await _confirmDelete(
      isThread ? Lc.current.deletePostConfirm : Lc.current.deleteFloorConfirm,
      isThread ? Lc.current.deleteThreadBody : Lc.current.deleteFloorBody,
    );
    if (!ok) return;
    try {
      if (isThread) {
        await Api.delete('/t/${widget.threadId}');
        if (!mounted) return;
        _toast(Lc.current.postDeleted);
        _close(true);
      } else {
        await Api.delete('/c/$id');
        await _reload();
      }
    } on ApiException catch (e) {
      _toast(e);
    }
  }

  Future<void> _recallReply(Map<String, dynamic> post) async {
    if (!AppState.instance.loggedIn) {
      _toast(Lc.current.needLogin);
      return;
    }
    final id = (post['id'] ?? 0) as int;
    if (id == 0) return;
    try {
      await Api.post('/c/$id/recall', const {});
      if (!mounted) return;
      _toast(Lc.current.dmRecalledMine);
      await _reload();
    } on ApiException catch (e) {
      _toast(e);
    }
  }

  Future<void> _recallSub(Map<String, dynamic> sub) async {
    if (!AppState.instance.loggedIn) {
      _toast(Lc.current.needLogin);
      return;
    }
    try {
      await Api.post('/c/${sub['id']}/recall', const {});
      if (!mounted) return;
      _toast(Lc.current.dmRecalledMine);
      await _reload();
    } on ApiException catch (e) {
      _toast(e);
    }
  }

  Future<void> _deleteSub(Map<String, dynamic> sub) async {
    if (!AppState.instance.loggedIn) {
      _toast(Lc.current.needLogin);
      return;
    }
    final ok = await _confirmDelete(
      Lc.current.deleteReplyConfirm,
      Lc.current.cannotUndo,
    );
    if (!ok) return;
    try {
      await Api.delete('/c/${sub['id']}');
      await _reload();
    } on ApiException catch (e) {
      _toast(e);
    }
  }

  Future<void> _agree(Map<String, dynamic> post) async {
    if (!AppState.instance.loggedIn) {
      _toast(Lc.current.needLogin);
      return;
    }
    final id = post['id'] as int;
    if (id == 0) return; // 1 楼没有独立记录，不能赞
    Haptics.done();
    try {
      final d = await Api.post('/agree/reply/$id', {});
      setState(() {
        post['agree_count'] =
            ((post['agree_count'] ?? 0) as int) +
            (d['agreed'] == true ? 1 : -1);
        post['agreed'] = d['agreed'];
      });
    } on ApiException catch (e) {
      _toast(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // 一楼并进头部，不再单独占一块
    final opIdx = _posts.indexWhere((p) => (p['floor'] ?? 0) == 1);
    final op = opIdx >= 0 ? _posts[opIdx] : null;
    final rest = _shownList();
    _shownLen = rest.length;

    return Scaffold(
      appBar: AppBar(
        // 嵌在右栏时不装返回箭头，改成一个关掉右栏的叉。
        automaticallyImplyLeading: !widget.embedded,
        leading: widget.embedded
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _close,
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              )
            : null,
        // 标题双击回顶。滚到第几十楼想回开头，比找浮标顺手。
        title: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTap: _toTop,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (_thread != null)
            PopupMenuButton<String>(
              tooltip: Lc.current.more,
              onSelected: (v) {
                if (v == 'only') {
                  setState(() => _onlyAuthor = !_onlyAuthor);
                }
                if (v == 'floor') _jumpToFloor();
                if (v == 'edit') _editThread();
                if (v == 'del') _deleteThread();
                if (v == 'wipe') _wipeImages();
                if (v == 'top') _adminToggle('top');
                if (v == 'good') _adminToggle('good');
                if (v == 'report') _reportThread();
                if (v == 'share') _shareThread();
              },
              itemBuilder: (_) => [
                PopupMenuItem<String>(
                  value: 'only',
                  child: Row(
                    children: [
                      Icon(
                        _onlyAuthor ? Icons.check : Icons.person_outline,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _onlyAuthor
                            ? Lc.current.onlyAuthorOn
                            : Lc.current.onlyAuthorOff,
                      ),
                    ],
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'floor',
                  child: Row(
                    children: [
                      const Icon(Icons.tag, size: 18),
                      const SizedBox(width: 10),
                      Text(
                        _pages > 1
                            ? Lc.current.jumpToFloorPages('$_pages')
                            : Lc.current.jumpToFloor,
                      ),
                    ],
                  ),
                ),
                if (AppState.instance.user?['is_admin'] == true)
                  PopupMenuItem<String>(
                    value: 'top',
                    child: Row(
                      children: [
                        Icon(
                          _thread!['is_top'] == true
                              ? Icons.push_pin
                              : Icons.push_pin_outlined,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _thread!['is_top'] == true
                              ? Lc.current.unpin
                              : Lc.current.pinned,
                        ),
                      ],
                    ),
                  ),
                if (AppState.instance.user?['is_admin'] == true)
                  PopupMenuItem<String>(
                    value: 'good',
                    child: Row(
                      children: [
                        Icon(
                          _thread!['is_good'] == true
                              ? Icons.star
                              : Icons.star_border,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _thread!['is_good'] == true
                              ? Lc.current.unfeature
                              : Lc.current.feature,
                        ),
                      ],
                    ),
                  ),
                if (_thread!['can_edit'] == true)
                  PopupMenuItem<String>(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined, size: 18),
                        SizedBox(width: 10),
                        Text(Lc.current.editPost),
                      ],
                    ),
                  ),
                if (AppState.instance.user?['is_admin'] == true)
                  PopupMenuItem<String>(
                    value: 'wipe',
                    child: Row(
                      children: [
                        Icon(Icons.hide_image_outlined, size: 18),
                        SizedBox(width: 10),
                        Text(Lc.current.replaceAllImages),
                      ],
                    ),
                  ),
                if (_thread!['can_delete'] == true)
                  PopupMenuItem<String>(
                    value: 'del',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, size: 18),
                        SizedBox(width: 10),
                        Text(Lc.current.deletePost),
                      ],
                    ),
                  ),
                PopupMenuItem<String>(
                  value: 'share',
                  child: Row(
                    children: [
                      const Icon(Icons.share_outlined, size: 18),
                      const SizedBox(width: 10),
                      Text(Lc.current.share),
                    ],
                  ),
                ),
                if (AppState.instance.loggedIn &&
                    AppState.instance.user?['id'] != _thread!['owner_id'])
                  PopupMenuItem<String>(
                    value: 'report',
                    child: Row(
                      children: [
                        Icon(Icons.flag_outlined, size: 18),
                        SizedBox(width: 10),
                        Text(Lc.current.report),
                      ],
                    ),
                  ),
              ],
            ),
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
            tooltip: Lc.current.refresh,
          ),
        ],
      ),
      body: PageWidth(
        child: _first
            ? const SkeletonList(count: 4)
            : Column(
                children: [
                  if (_err != null)
                    Container(
                      width: double.infinity,
                      color: cs.errorContainer,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Text(
                        _err!,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onErrorContainer,
                        ),
                      ),
                    ),
                  Expanded(
                    child: Stack(
                      children: [
                        RefreshIndicator(
                          onRefresh: _pullRefresh,
                          child: ScrollablePositionedList.builder(
                            itemScrollController: _itemScroll,
                            itemPositionsListener: _posListener,
                            // 内容只有一屏时也要能拉得动，不然刷新做不了
                            physics: const AlwaysScrollableScrollPhysics(),
                            itemCount:
                                rest.length + 1 + (_moreErr == null ? 0 : 1),
                            itemBuilder: (context, i) {
                              if (i == 0) return _header(cs, op);
                              if (i > rest.length) return _moreBar(cs);
                              final p = rest[i - 1];
                              return _PostCard(
                                post: p,
                                highlight:
                                    _flashFloor > 0 &&
                                    (p['floor'] ?? 0) == _flashFloor,
                                onReply: () => _beginReply(p),
                                onAgree: () => _agree(p),
                                onEdit: p['can_edit'] == true
                                    ? () => _editReply(p)
                                    : null,
                                onRecall: p['can_recall'] == true
                                    ? () => _recallReply(p)
                                    : null,
                                onDelete:
                                    (p['can_delete'] == true &&
                                        (p['floor'] ?? 0) != 1)
                                    ? () => _deletePost(p)
                                    : null,
                                onDeleteSub: _deleteSub,
                                onRecallSub: _recallSub,
                                onReport: (p['floor'] ?? 0) == 1
                                    ? _reportThread
                                    : () => _reportReply(p),
                              );
                            },
                          ),
                        ),
                        Positioned(
                          right: 14,
                          bottom: 14,
                          child: _backTop(cs),
                        ),
                      ],
                    ),
                  ),
                  // 输入栏放在 body 里而不是 bottomNavigationBar：
                  // 后者在键盘弹出时不上浮，会被盖住。
                  _replyBar(cs),
                ],
              ),
      ),
    );
  }

  Widget _header(ColorScheme cs, Map<String, dynamic>? op) {
    final t = _thread;
    if (t == null || op == null) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final author = (t['author'] ?? '') as String;
    final handle = (t['handle'] ?? '') as String;
    final avatar = (t['author_avatar'] ?? '') as String;
    final body = (op['body'] ?? '') as String;
    final title = ((t['title'] ?? widget.title) as String).trim();
    final imgs = ((op['images'] as List?) ?? const []).cast<String>();
    final files = PostFile.listOf(op['files']);
    final sizes = (op['img_sizes'] as List?) ?? const [];
    final created = (t['created_at'] ?? 0) as int;
    final views = (t['view_count'] ?? 0) as int;
    final replies = (t['reply_count'] ?? 0) as int;
    final agree = (t['agree_count'] ?? 0) as int;
    final agreed = t['agreed'] == true;
    final faved = t['faved'] == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 楼主这层跟下面的楼层用同一种卡片，不然上半截平铺、下半截卡片会断层。
        AppCard(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          color: hueCardTint(
            hueOfUser(op),
            Theme.of(context).brightness == Brightness.dark,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: () => openUserPage(context, handle),
                    child: CircleAvatarImg(
                      url: avatar,
                      name: author,
                      radius: 22,
                      hue: hueOfUser(t),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        NameTag(
                          name: author,
                          handle: handle,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (title.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 19,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              if (body.isNotEmpty)
                RichBody(
                  body,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.5,
                    color: cs.onSurface,
                  ),
                ),
              if (imgs.isNotEmpty) ...[
                const SizedBox(height: 10),
                PostImages(
                  urls: imgs,
                  sizes: sizes,
                  heroPrefix: 'p${t['id']}',
                ),
              ],
              if (files.isNotEmpty) FileCards(files: files),
              const SizedBox(height: 10),
              Text(
                [
                  postTime(created),
                  Lc.current.viewsCount(bigNum(views)),
                  if (((op['edited_at'] ?? 0) as int) > 0) Lc.current.edited,
                ].join(' · '),
                style: TextStyle(fontSize: 12, color: cs.outline),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  _statIcon(
                    cs,
                    Icons.mode_comment_outlined,
                    replies > 0 ? bigNum(replies) : null,
                    () => _beginReply(op),
                  ),
                  const SizedBox(width: 24),
                  _statIcon(
                    cs,
                    agreed ? Icons.favorite : Icons.favorite_border,
                    agree > 0 ? bigNum(agree) : null,
                    _agreeThread,
                    active: agreed,
                  ),
                  const SizedBox(width: 24),
                  _statIcon(
                    cs,
                    faved ? Icons.bookmark : Icons.bookmark_border,
                    null,
                    _toggleFav,
                    active: faved,
                  ),
                  const Spacer(),
                  if (t['can_delete'] == true)
                    GestureDetector(
                      onTap: _deleteThread,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          Icons.delete_outline,
                          size: 18,
                          color: cs.outline,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Text(
                Lc.current.related,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 4),
              Icon(Icons.keyboard_arrow_down, size: 18, color: cs.outline),
              const Spacer(),
              Text(
                replies > 0
                    ? Lc.current.repliesCount(bigNum(replies))
                    : Lc.current.noReplies,
                style: TextStyle(fontSize: 12, color: cs.outline),
              ),
            ],
          ),
        ),
        // 一条回复都没有的时候，下半截会是一大片空白，
        // 给个能点的地方，别让人以为页面没加载完。
        if (replies == 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
            child: AppCard(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 26),
              child: Column(
                children: [
                  Icon(Icons.forum_outlined, size: 26, color: cs.outline),
                  const SizedBox(height: 10),
                  Text(
                    Lc.current.noRepliesHint,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: cs.outline),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _statIcon(
    ColorScheme cs,
    IconData icon,
    String? label,
    VoidCallback onTap, {
    bool active = false,
  }) {
    final color = active ? cs.primary : cs.outline;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 17, color: color),
            if (label != null) ...[
              const SizedBox(width: 5),
              Text(label, style: TextStyle(fontSize: 12, color: color)),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _toggleFav() async {
    if (!AppState.instance.loggedIn) {
      _toast(Lc.current.needLogin);
      return;
    }
    final t = _thread;
    if (t == null) return;
    try {
      final d = await Api.post('/fav/${t['id']}', {});
      if (!mounted) return;
      setState(() => t['faved'] = d['faved'] == true);
      _toast(d['faved'] == true ? Lc.current.favorited : Lc.current.unfavorite);
    } on ApiException catch (e) {
      _toast(e);
    }
  }

  Future<void> _agreeThread() async {
    if (!AppState.instance.loggedIn) {
      _toast(Lc.current.needLogin);
      return;
    }
    final t = _thread;
    if (t == null) return;
    try {
      final d = await Api.post('/agree/thread/${t['id']}', {});
      setState(() {
        t['agree_count'] =
            ((t['agree_count'] ?? 0) as int) + (d['agreed'] == true ? 1 : -1);
        t['agreed'] = d['agreed'];
      });
    } on ApiException catch (e) {
      _toast(e);
    }
  }

  Widget _replyBar(ColorScheme cs) {
    final me = AppState.instance.user;
    final meAvatar = (me?['avatar'] ?? '') as String;
    final meName =
        ((me?['nickname'] ?? me?['name'] ?? Lc.current.meShort) as Object)
            .toString();
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border(
            top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_imgs.isNotEmpty) ...[
              _replyThumbs(cs),
              const SizedBox(height: 8),
            ],
            if (_files.isNotEmpty)
              EditableFileCards(
                files: _files,
                busy: _sending,
                onRemove: (f) => setState(() => _files.remove(f)),
              ),
            if (_replyTo != null)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      Lc.current.replyTo((_replyTo!['author'] ?? '') as String),
                      style: TextStyle(fontSize: 12, color: cs.primary),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _replyTo = null),
                      child: Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Icon(Icons.close, size: 14, color: cs.outline),
                      ),
                    ),
                  ],
                ),
              ),
            MentionStrip(watcher: _mention, controller: _input),
            Row(
              children: [
                CircleAvatarImg(
                  url: meAvatar,
                  name: meName,
                  radius: 16,
                  hue: AppState.instance.accentHue.value,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _input,
                    focusNode: _inputFocus,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.newline,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: cs.surfaceContainerHighest,
                      hintText: Lc.current.replyHint,
                      hintStyle: TextStyle(fontSize: 14, color: cs.outline),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: _sending ? null : _pickFile,
                  icon: const Icon(Icons.attach_file, size: 20),
                  tooltip: Lc.current.attachFile,
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: (_sending || _compressing) ? null : _pickImages,
                  icon: _compressing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.image_outlined, size: 22),
                  tooltip: Lc.current.addImageShort,
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: _sending ? null : _send,
                  icon: _sending
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded, size: 20),
                  color: cs.primary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _replyThumbs(ColorScheme cs) {
    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _imgs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (c, i) => Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: Image.memory(
                _imgs[i],
                width: 56,
                height: 56,
                fit: BoxFit.cover,
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              child: GestureDetector(
                onTap: () => setState(() => _imgs.removeAt(i)),
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(1.5),
                  child: const Icon(Icons.close, size: 11, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 传附件。大包传得慢，这中间发送按钮是锁着的，传完解锁。
  Future<void> _pickFile() async {
    if (_files.length >= 5) {
      _toast(Lc.current.attachMax('5'));
      return;
    }
    final f = await pickFile();
    if (f == null) return;
    if (f.size > 500 * 1024 * 1024) {
      _toast(Lc.current.attachTooBig('500MB'));
      return;
    }
    setState(() => _sending = true);
    try {
      final r = await Api.uploadFile(f);
      if (!mounted) return;
      setState(
        () => _files.add(
          PostFile(
            url: '${r['url']}',
            name: '${r['name']}',
            size: r['size'] is int ? r['size'] as int : f.size,
          ),
        ),
      );
    } catch (e) {
      _toast(e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickImages() async {
    if (_imgs.length >= 9) {
      _toast(Lc.current.maxNineImages);
      return;
    }
    if (_compressing) return;
    try {
      final picked = !hasMediaStore
          ? await _picker.pickMultiImage()
          : await pickOwnGallery(context, maxCount: 9 - _imgs.length);
      if (picked.isEmpty) return;
      setState(() => _compressing = true);
      for (final x in picked.take(9 - _imgs.length)) {
        final raw = await x.readAsBytes();
        final b = await ImgCompress.run(raw);
        if (ImgCompress.tooBig(b)) {
          _toast(Lc.current.imageStillTooBig);
          continue;
        }
        _imgs.add(b);
      }
      if (mounted) setState(() {});
    } catch (e) {
      _toast(Lc.current.albumFailed('$e'));
    } finally {
      if (mounted) setState(() => _compressing = false);
    }
  }
}

/// 一层楼。
class _PostCard extends StatefulWidget {
  final Map<String, dynamic> post;
  final VoidCallback onAgree;
  final VoidCallback onReply;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onRecall;
  final ValueChanged<Map<String, dynamic>>? onDeleteSub;
  final ValueChanged<Map<String, dynamic>>? onRecallSub;
  final VoidCallback? onReport;

  /// 刚跳过来的那一层，底色淡一下
  final bool highlight;

  const _PostCard({
    required this.post,
    required this.onAgree,
    required this.onReply,
    this.onEdit,
    this.onDelete,
    this.onRecall,
    this.onDeleteSub,
    this.onRecallSub,
    this.onReport,
    this.highlight = false,
  });

  @override
  State<_PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<_PostCard> {
  bool _all = false;

  Future<void> _moreSheet() async {
    Haptics.press();
    final act = await showAppSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.onEdit != null)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(Lc.current.edit),
                onTap: () => Navigator.of(c).pop('edit'),
              ),
            if (widget.onRecall != null)
              ListTile(
                leading: const Icon(Icons.undo),
                title: Text(Lc.current.dmRecall),
                subtitle: Text(Lc.current.replyRemembered),
                onTap: () => Navigator.of(c).pop('recall'),
              ),
            if (widget.onDelete != null)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text(Lc.current.delete),
                onTap: () => Navigator.of(c).pop('del'),
              ),
            if (widget.onReport != null)
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: Text(Lc.current.report),
                onTap: () => Navigator.of(c).pop('report'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (act == 'edit') widget.onEdit?.call();
    if (act == 'recall') widget.onRecall?.call();
    if (act == 'del') widget.onDelete?.call();
    if (act == 'report') widget.onReport?.call();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final post = widget.post;
    final author = (post['author'] ?? '') as String;
    final handle = (post['handle'] ?? '') as String;
    final avatar = (post['author_avatar'] ?? '') as String;
    final bodyText = (post['body'] ?? '') as String;
    final imgs = ((post['images'] as List?) ?? const []).cast<String>();
    final files = PostFile.listOf(post['files']);
    final sizes = (post['img_sizes'] as List?) ?? const [];
    final subs = ((post['subs'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    final agree = (post['agree_count'] ?? 0) as int;
    final agreed = post['agreed'] == true;
    final created = (post['created_at'] ?? 0) as int;
    final isOp = post['is_op'] == true;
    final recalled = post['recalled'] == true;
    final liked = agreed ? cs.primary : cs.outline;
    // 这一层是谁的，描边里看得见。淡，但一层一层扫下去能分出人。
    final dark = Theme.of(context).brightness == Brightness.dark;
    final authHue = hueOfUser(post);
    final tint = hueCardTint(authHue, dark);

    // 楼层走卡片：和列表页一个语言，跳楼时靠描边和底色提示位置。
    return AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        // 这一层是谁的，底色就是谁的；开关关掉就是默认底。
        // 跳楼高亮要叠在底色上，所以先算出底色再混。
        color: widget.highlight
            ? Color.alphaBlend(
                cs.primary.withValues(alpha: 0.10),
                tint ?? cs.surfaceContainerLow,
              )
            : tint,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.highlight
              ? hueRing(authHue, dark).withValues(alpha: 0.75)
              : hueRing(authHue, dark).withValues(alpha: dark ? 0.22 : 0.30),
        ),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onLongPress: _moreSheet,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: () => openUserPage(context, handle),
                    child: CircleAvatarImg(
                      url: avatar,
                      name: author,
                      radius: 19,
                      hue: hueOfUser(post),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                author,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (isOp)
                              Container(
                                margin: const EdgeInsets.only(left: 5),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: cs.primary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  Lc.current.opAuthor,
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: cs.primary,
                                  ),
                                ),
                              ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                [
                                  if (handle.isNotEmpty) '@$handle',
                                  timeAgo(created),
                                  if (((post['edited_at'] ?? 0) as int) > 0)
                                    Lc.current.edited,
                                ].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.outline,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        if (recalled)
                          Padding(
                            padding: const EdgeInsets.only(top: 2, bottom: 2),
                            child: Text(
                              Lc.current.replyRecalled,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.5,
                                fontStyle: FontStyle.italic,
                                color: cs.outline,
                              ),
                            ),
                          )
                        else
                          RichBody(
                            bodyText,
                            style: const TextStyle(fontSize: 14, height: 1.5),
                            contextMenuBuilder: (ctx, editable) =>
                                AdaptiveTextSelectionToolbar.buttonItems(
                                  anchors: editable.contextMenuAnchors,
                                  buttonItems: [
                                    ContextMenuButtonItem(
                                      label: Lc.current.copyFullText,
                                      onPressed: () {
                                        Clipboard.setData(
                                          ClipboardData(text: bodyText),
                                        );
                                        editable.hideToolbar();
                                        _toastOf(ctx, Lc.current.copied);
                                      },
                                    ),
                                    ...editable.contextMenuButtonItems,
                                  ],
                                ),
                          ),
                        if (!recalled && imgs.isNotEmpty)
                          PostImages(
                            urls: imgs,
                            sizes: sizes,
                            heroPrefix: 'p${widget.post['id']}',
                          ),
                        if (!recalled && files.isNotEmpty)
                          FileCards(files: files),
                        if (!recalled && subs.isNotEmpty) _subThread(cs, subs),
                        if (subs.length > 3)
                          GestureDetector(
                            onTap: () => setState(() => _all = !_all),
                            behavior: HitTestBehavior.opaque,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 6, bottom: 2),
                              child: Text(
                                _all
                                    ? Lc.current.collapse
                                    : Lc.current.expandAllReplies(
                                        '${subs.length}',
                                      ),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.primary,
                                ),
                              ),
                            ),
                          ),
                        if (!recalled) ...[
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              InkWell(
                                onTap: widget.onReply,
                                borderRadius: BorderRadius.circular(4),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 2,
                                    vertical: 6,
                                  ),
                                  child: Icon(
                                    Icons.mode_comment_outlined,
                                    size: 16,
                                    color: cs.outline,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 22),
                              InkWell(
                                onTap: widget.onAgree,
                                borderRadius: BorderRadius.circular(4),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 2,
                                    vertical: 6,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        agreed
                                            ? Icons.favorite
                                            : Icons.favorite_border,
                                        size: 16,
                                        color: liked,
                                      ),
                                      if (agree > 0) ...[
                                        const SizedBox(width: 5),
                                        Text(
                                          bigNum(agree),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: liked,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (widget.onDelete != null ||
                      widget.onEdit != null ||
                      widget.onRecall != null)
                    GestureDetector(
                      onTap: _moreSheet,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 4, top: 2),
                        child: Icon(
                          Icons.more_horiz,
                          size: 18,
                          color: cs.outline,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  Widget _subThread(ColorScheme cs, List<Map<String, dynamic>> subs) {
    final shown = (_all || subs.length <= 3) ? subs : subs.take(3);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.only(left: 10),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final s in shown)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${s['author']}：',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: cs.primary,
                            ),
                          ),
                          TextSpan(
                            text: s['recalled'] == true
                                ? Lc.current.replyRecalled
                                : '${s['body']}',
                            style: s['recalled'] == true
                                ? TextStyle(
                                    fontStyle: FontStyle.italic,
                                    color: cs.outline,
                                  )
                                : null,
                          ),
                        ],
                      ),
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                  if (s['can_recall'] == true)
                    GestureDetector(
                      onTap: () => widget.onRecallSub?.call(s),
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8, top: 2),
                        child: Icon(Icons.undo, size: 14, color: cs.outline),
                      ),
                    ),
                  if (s['can_delete'] == true)
                    GestureDetector(
                      onTap: () => widget.onDeleteSub?.call(s),
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8, top: 2),
                        child: Icon(
                          Icons.delete_outline,
                          size: 14,
                          color: cs.outline,
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

void _toastOf(BuildContext ctx, String msg) {
  toast(ctx, msg, floating: true);
}
