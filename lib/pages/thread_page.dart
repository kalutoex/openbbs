import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../api.dart';
import '../plat.dart';
import '../widgets/mention.dart';
import '../store.dart';
import '../img_compress.dart';
import 'gallery_picker_page.dart';
import 'edit_thread_page.dart';
import '../utils.dart';
import '../widgets/avatar.dart';
import '../widgets/name_tag.dart';
import '../widgets/post_images.dart';
import '../widgets/skeleton.dart';
import '../widgets/user_link.dart';

/// 帖子详情：楼层 + 楼中楼。
class ThreadPage extends StatefulWidget {
  final int threadId;
  final String title;

  /// 从通知进来时带楼层 id，加载完自动滚过去。
  final int? focusPostId;

  const ThreadPage({
    super.key,
    required this.threadId,
    required this.title,
    this.focusPostId,
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

  int? _ownerId;

  /// 正在回复的楼层；null 表示回复楼主
  Map<String, dynamic>? _replyTo;

  final ImagePicker _picker = ImagePicker();
  final List<Uint8List> _imgs = [];
  bool _compressing = false;

  @override
  void initState() {
    super.initState();
    _input.addListener(_onMention);
    // 资料可能在别处改过，进帖子页时对一次，底栏头像才不会停在旧的
    AppState.instance.refreshUser();
    _posListener.itemPositions.addListener(() {
      final ps = _posListener.itemPositions.value;
      if (ps.isEmpty) return;
      var last = 0;
      for (final e in ps) {
        if (e.index > last) last = e.index;
      }
      // 提前量按这一屏摆得下几楼来算，滑到底时下一页已经在手上。
      final ahead = ps.length + 2;
      if (last >= _shownLen - ahead) _loadMore();
    });
    _boot();
  }

  /// 有 focusPostId 就先把目标页加载出来，再滚过去。
  Future<void> _boot() async {
    final fid = widget.focusPostId;
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
        title: const Text('跳转楼层'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(hintText: '输入楼层号，比如 128'),
          onSubmitted: (v) => Navigator.of(ctx).pop(int.tryParse(v)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(int.tryParse(ctl.text)),
            child: const Text('跳'),
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
      _toast(_page <= _pages ? '还没翻到第 $n 楼' : '没有第 $n 楼');
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
    _input.removeListener(_onMention);
    _mention.dispose();
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
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
        _err = cached ? '网络不通，下面是上次缓存的内容' : null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _first = false;
        _err = e.message;
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
    });
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
      _toast('先登录');
      return;
    }
    final body = _input.text.trim();
    if ((body.isEmpty && _imgs.isEmpty) || _sending) return;
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
      });
      _input.clear();
      if (mounted) {
        setState(() {
          _replyTo = null;
          _sending = false;
          _imgs.clear();
        });
      }
      await _refreshTail();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      _toast(e.message);
    }
  }

  void _toast(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  void _beginReply(Map<String, dynamic> post) {
    if (!AppState.instance.loggedIn) {
      _toast('先登录');
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
      _toast(kind == 'top' ? (on ? '已置顶' : '已取消置顶') : (on ? '已加精' : '已取消加精'));
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  /// 选个举报理由，取消返回 null。
  Future<String?> _pickReason() {
    return showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '举报理由',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
            for (final r in const ['垃圾广告', '人身攻击', '违法违规', '内容不实', '其他'])
              ListTile(title: Text(r), onTap: () => Navigator.of(ctx).pop(r)),
          ],
        ),
      ),
    );
  }

  Future<void> _sendReport(Map<String, dynamic> body) async {
    try {
      final r = await Api.post('/report', body);
      _toast(r['duplicate'] == true ? '已经报过一次了' : '收到了，会看');
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  /// 举报整帖。
  Future<void> _reportThread() async {
    final t = _thread;
    if (t == null) return;
    if (!AppState.instance.loggedIn) {
      _toast('先登录');
      return;
    }
    final reason = await _pickReason();
    if (reason == null) return;
    await _sendReport({'thread_id': t['id'], 'reason': reason});
  }

  /// 举报某一层。
  Future<void> _reportReply(Map<String, dynamic> post) async {
    if (!AppState.instance.loggedIn) {
      _toast('先登录');
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
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  /// 改自己的帖子。图片在编辑页里增删，这里只负责把结果拿回来。
  Future<void> _editThread() async {
    if (!AppState.instance.loggedIn) {
      _toast('先登录');
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
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EditThreadPage(
          tid: widget.threadId,
          title: (t['title'] ?? widget.title) as String,
          body: (op['body'] ?? '') as String,
          images: imgs,
        ),
      ),
    );
    if (changed == true && mounted) {
      _toast('改好了');
      await _reload();
    }
  }

  /// 改回复：只动正文，配图原样留着。
  Future<void> _editReply(Map<String, dynamic> post) async {
    if (!AppState.instance.loggedIn) {
      _toast('先登录');
      return;
    }
    final id = (post['id'] ?? 0) as int;
    final ctrl = TextEditingController(text: (post['body'] ?? '') as String);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('改这一楼'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          minLines: 3,
          maxLines: 8,
          maxLength: 20000,
          decoration: const InputDecoration(
            hintText: '说点什么…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('保存'),
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
      _toast('改好了');
      await _reload();
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  /// 管理员：把这一帖（含回复）里的图全换成占位图。
  Future<void> _wipeImages() async {
    final ok = await _confirmDelete(
      '换成占位图？',
      '这一帖和下面所有回复里的图都会换成同一张占位图，原图找不回来。',
    );
    if (!ok) return;
    try {
      final d = await Api.post('/t/${widget.threadId}/replace-images', {});
      if (!mounted) return;
      _toast('已换掉 ${d['changed'] ?? 0} 张图');
      _reload();
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _deleteThread() async {
    if (!AppState.instance.loggedIn) {
      _toast('先登录');
      return;
    }
    final ok = await _confirmDelete('删除这帖？', '帖子和下面所有回复一起消失，删了找不回来。');
    if (!ok) return;
    try {
      await Api.delete('/t/${widget.threadId}');
      if (!mounted) return;
      _toast('帖子已删');
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _deletePost(Map<String, dynamic> post) async {
    if (!AppState.instance.loggedIn) {
      _toast('先登录');
      return;
    }
    final id = (post['id'] ?? 0) as int;
    final isThread = (post['floor'] ?? 0) == 1;
    final ok = await _confirmDelete(
      isThread ? '删除这帖？' : '删除这楼？',
      isThread ? '帖子连同所有回复一起删掉，删了不能恢复。' : '这楼和它下面的楼中楼一起删掉。',
    );
    if (!ok) return;
    try {
      if (isThread) {
        await Api.delete('/t/${widget.threadId}');
        if (!mounted) return;
        _toast('帖子已删');
        Navigator.of(context).pop(true);
      } else {
        await Api.delete('/c/$id');
        await _reload();
      }
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _deleteSub(Map<String, dynamic> sub) async {
    if (!AppState.instance.loggedIn) {
      _toast('先登录');
      return;
    }
    final ok = await _confirmDelete('删除这条回复？', '删了不能恢复。');
    if (!ok) return;
    try {
      await Api.delete('/c/${sub['id']}');
      await _reload();
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _agree(Map<String, dynamic> post) async {
    if (!AppState.instance.loggedIn) {
      _toast('先登录');
      return;
    }
    final id = post['id'] as int;
    if (id == 0) return; // 1 楼没有独立记录，不能赞
    try {
      final d = await Api.post('/agree/reply/$id', {});
      setState(() {
        post['agree_count'] =
            ((post['agree_count'] ?? 0) as int) +
            (d['agreed'] == true ? 1 : -1);
        post['agreed'] = d['agreed'];
      });
    } on ApiException catch (e) {
      _toast(e.message);
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
    final forumLabel = ((_thread?['forum_title'] ?? '') as String).trim();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            if (forumLabel.isNotEmpty)
              Text(
                forumLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
          ],
        ),
        actions: [
          if (_thread != null)
            PopupMenuButton<String>(
              tooltip: '更多',
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
                      Text(_onlyAuthor ? '已只看楼主' : '只看楼主'),
                    ],
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'floor',
                  child: Row(
                    children: [
                      const Icon(Icons.tag, size: 18),
                      const SizedBox(width: 10),
                      Text(_pages > 1 ? '跳转楼层（共 $_pages 页）' : '跳转楼层'),
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
                        Text(_thread!['is_top'] == true ? '取消置顶' : '置顶'),
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
                        Text(_thread!['is_good'] == true ? '取消加精' : '加精'),
                      ],
                    ),
                  ),
                if (_thread!['can_edit'] == true)
                  const PopupMenuItem<String>(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined, size: 18),
                        SizedBox(width: 10),
                        Text('编辑帖子'),
                      ],
                    ),
                  ),
                if (AppState.instance.user?['is_admin'] == true)
                  const PopupMenuItem<String>(
                    value: 'wipe',
                    child: Row(
                      children: [
                        Icon(Icons.hide_image_outlined, size: 18),
                        SizedBox(width: 10),
                        Text('一键替换图片'),
                      ],
                    ),
                  ),
                if (_thread!['can_delete'] == true)
                  const PopupMenuItem<String>(
                    value: 'del',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, size: 18),
                        SizedBox(width: 10),
                        Text('删除帖子'),
                      ],
                    ),
                  ),
                if (AppState.instance.loggedIn &&
                    AppState.instance.user?['id'] != _thread!['owner_id'])
                  const PopupMenuItem<String>(
                    value: 'report',
                    child: Row(
                      children: [
                        Icon(Icons.flag_outlined, size: 18),
                        SizedBox(width: 10),
                        Text('举报'),
                      ],
                    ),
                  ),
              ],
            ),
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
          ),
        ],
      ),
      body: _first
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
                  child: ScrollablePositionedList.builder(
                    itemScrollController: _itemScroll,
                    itemPositionsListener: _posListener,
                    itemCount: rest.length + 1,
                    itemBuilder: (context, i) {
                      if (i == 0) return _header(cs, op);
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
                        onDelete:
                            (p['can_delete'] == true && (p['floor'] ?? 0) != 1)
                            ? () => _deletePost(p)
                            : null,
                        onDeleteSub: _deleteSub,
                        onReport: (p['floor'] ?? 0) == 1
                            ? _reportThread
                            : () => _reportReply(p),
                      );
                    },
                  ),
                ),
                // 输入栏放在 body 里而不是 bottomNavigationBar：
                // 后者在键盘弹出时不上浮，会被盖住。
                _replyBar(cs),
              ],
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
    final forum = (t['forum'] ?? '') as String;
    final body = (op['body'] ?? '') as String;
    final title = ((t['title'] ?? widget.title) as String).trim();
    final imgs = ((op['images'] as List?) ?? const []).cast<String>();
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
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
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
                  if (forum.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        forum,
                        style: TextStyle(fontSize: 12, color: cs.outline),
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
                PostImages(urls: imgs, sizes: sizes),
              ],
              const SizedBox(height: 10),
              Text(
                [
                  postTime(created),
                  '${bigNum(views)} 浏览',
                  if (((op['edited_at'] ?? 0) as int) > 0) '已编辑',
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
        Container(height: 8, color: cs.surfaceContainerHighest),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              const Text(
                '相关',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 4),
              Icon(Icons.keyboard_arrow_down, size: 18, color: cs.outline),
              const Spacer(),
              Text(
                replies > 0 ? '${bigNum(replies)} 条回复' : '还没有回复',
                style: TextStyle(fontSize: 12, color: cs.outline),
              ),
            ],
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
      _toast('先登录');
      return;
    }
    final t = _thread;
    if (t == null) return;
    try {
      final d = await Api.post('/fav/${t['id']}', {});
      if (!mounted) return;
      setState(() => t['faved'] = d['faved'] == true);
      _toast(d['faved'] == true ? '已收藏' : '取消收藏');
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _agreeThread() async {
    if (!AppState.instance.loggedIn) {
      _toast('先登录');
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
      _toast(e.message);
    }
  }

  Widget _replyBar(ColorScheme cs) {
    final me = AppState.instance.user;
    final meAvatar = (me?['avatar'] ?? '') as String;
    final meName = ((me?['nickname'] ?? me?['name'] ?? '我') as Object)
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
            if (_replyTo != null)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '回复 ${(_replyTo!['author'] ?? '') as String}',
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
                CircleAvatarImg(url: meAvatar, name: meName, radius: 16),
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
                      hintText: '发布你的回复',
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
                  onPressed: (_sending || _compressing) ? null : _pickImages,
                  icon: _compressing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.image_outlined, size: 22),
                  tooltip: '加图',
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

  Future<void> _pickImages() async {
    if (_imgs.length >= 9) {
      _toast('最多 9 张');
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
          _toast('有张图压完还是太大，跳过了');
          continue;
        }
        _imgs.add(b);
      }
      if (mounted) setState(() {});
    } catch (e) {
      _toast('打不开相册：$e');
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
  final ValueChanged<Map<String, dynamic>>? onDeleteSub;
  final VoidCallback? onReport;

  /// 刚跳过来的那一层，底色淡一下
  final bool highlight;

  const _PostCard({
    required this.post,
    required this.onAgree,
    required this.onReply,
    this.onEdit,
    this.onDelete,
    this.onDeleteSub,
    this.onReport,
    this.highlight = false,
  });

  @override
  State<_PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<_PostCard> {
  bool _all = false;

  Future<void> _moreSheet() async {
    final act = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.onEdit != null)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('编辑'),
                onTap: () => Navigator.of(c).pop('edit'),
              ),
            if (widget.onDelete != null)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('删除'),
                onTap: () => Navigator.of(c).pop('del'),
              ),
            if (widget.onReport != null)
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: const Text('举报'),
                onTap: () => Navigator.of(c).pop('report'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (act == 'edit') widget.onEdit?.call();
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
    final sizes = (post['img_sizes'] as List?) ?? const [];
    final subs = ((post['subs'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    final agree = (post['agree_count'] ?? 0) as int;
    final agreed = post['agreed'] == true;
    final created = (post['created_at'] ?? 0) as int;
    final isOp = post['is_op'] == true;
    final liked = agreed ? cs.primary : cs.outline;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      color: widget.highlight
          ? cs.primary.withValues(alpha: 0.08)
          : Colors.transparent,
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
                  child: CircleAvatarImg(url: avatar, name: author, radius: 19),
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
                                '楼主',
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
                                  '已编辑',
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: cs.outline),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      RichBody(
                        bodyText,
                        style: const TextStyle(fontSize: 14, height: 1.5),
                        contextMenuBuilder: (ctx, editable) =>
                            AdaptiveTextSelectionToolbar.buttonItems(
                              anchors: editable.contextMenuAnchors,
                              buttonItems: [
                                ContextMenuButtonItem(
                                  label: '复制全文',
                                  onPressed: () {
                                    Clipboard.setData(
                                      ClipboardData(text: bodyText),
                                    );
                                    editable.hideToolbar();
                                    _toastOf(ctx, '已复制');
                                  },
                                ),
                                ...editable.contextMenuButtonItems,
                              ],
                            ),
                      ),
                      if (imgs.isNotEmpty)
                        PostImages(urls: imgs, sizes: sizes),
                      if (subs.isNotEmpty) _subThread(cs, subs),
                      if (subs.length > 3)
                        GestureDetector(
                          onTap: () => setState(() => _all = !_all),
                          behavior: HitTestBehavior.opaque,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 6, bottom: 2),
                            child: Text(
                              _all ? '收起' : '展开全部 ${subs.length} 条回复',
                              style: TextStyle(fontSize: 12, color: cs.primary),
                            ),
                          ),
                        ),
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
                  ),
                ),
                if (widget.onDelete != null || widget.onEdit != null)
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
          const SizedBox(height: 8),
          Divider(
            height: 1,
            indent: 62,
            color: cs.outlineVariant.withValues(alpha: 0.3),
          ),
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
                          TextSpan(text: '${s['body']}'),
                        ],
                      ),
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        color: cs.onSurface,
                      ),
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
  ScaffoldMessenger.of(ctx).showSnackBar(
    SnackBar(
      content: Text(msg),
      duration: const Duration(milliseconds: 1200),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
