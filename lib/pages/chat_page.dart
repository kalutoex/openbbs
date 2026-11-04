import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api.dart';
import '../img_compress.dart';
import '../store.dart';
import '../widgets/avatar.dart';
import '../l10n/error_text.dart';
import '../l10n/l10n.dart';
import 'user_page.dart';
import '../widgets/toast.dart';

/// 一对一私信。进页面拉最新 30 条，往上翻更早，15 秒轮询一次。
///
/// 不做长连接：这版的量用不着，WebSocket 还得在服务端多养一条连接。
class ChatPage extends StatefulWidget {
  final Map<String, dynamic> peer;

  const ChatPage({super.key, required this.peer});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final List<Map<String, dynamic>> _msgs = [];
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<Uint8List> _pending = [];
  final ImagePicker _picker = ImagePicker();
  bool _compressing = false;
  Timer? _poll;

  bool _loading = true;
  bool _sending = false;
  bool _hasMore = false;
  String? _err;

  int get _peerId => (widget.peer['id'] ?? 0) as int;
  String get _peerName =>
      (widget.peer['nickname'] ?? widget.peer['name'] ?? '') as String;

  @override
  void initState() {
    super.initState();
    _load(initial: true);
    _poll = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted || _sending) return;
      _load();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _load({bool initial = false}) async {
    try {
      final d = await Api.get('/dm/$_peerId');
      if (!mounted) return;
      final list = (d['items'] as List).cast<Map<String, dynamic>>();
      setState(() {
        _msgs
          ..clear()
          ..addAll(list);
        _hasMore = d['has_more'] == true;
        _loading = false;
        _err = null;
      });
      AppState.instance.refreshDmUnread();
      if (initial) {
        _toBottom();
      } else if (_atBottom) {
        // 只在本来就贴底的时候跟着滚，用户翻旧消息时不打扰
        _toBottom();
      }
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

  bool get _atBottom {
    if (!_scroll.hasClients) return true;
    return _scroll.position.pixels > _scroll.position.maxScrollExtent - 80;
  }

  Future<void> _loadEarlier() async {
    if (_msgs.isEmpty || !_hasMore) return;
    final before = (_msgs.first['id'] ?? 0) as int;
    try {
      final d = await Api.get('/dm/$_peerId', query: {'before_id': '$before'});
      final list = (d['items'] as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _msgs.insertAll(0, list);
        _hasMore = d['has_more'] == true;
      });
    } catch (_) {
      // 翻旧消息失败就失败吧，不动当前画面
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
      if (mounted) {
        toast(context, Lc.current.readImageFailed('$e'));
      }
    } finally {
      if (mounted) setState(() => _compressing = false);
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if ((text.isEmpty && _pending.isEmpty) || _sending) return;
    setState(() => _sending = true);
    try {
      // 先传图，拿到站内地址再发消息
      final urls = <String>[];
      for (final b in _pending) {
        urls.add(await Api.uploadImage(b));
      }
      await Api.post('/dm/$_peerId', {'body': text, 'images': urls});
      if (!mounted) return;
      _input.clear();
      setState(() {
        _pending.clear();
        _sending = false;
      });
      await _load();
      _toBottom();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      toast(context, errorText(context, e));
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      toast(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final avatar = (widget.peer['avatar'] ?? '') as String;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 4,
        title: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  UserPage(name: (widget.peer['name'] ?? '') as String),
            ),
          ),
          child: Row(
            children: [
              CircleAvatarImg(url: avatar, name: _peerName, radius: 16),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  _peerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(child: _msgArea(context)),
          _pending.isNotEmpty
              ? SizedBox(
                  height: 74,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    itemCount: _pending.length,
                    separatorBuilder: (_, i) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      return Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.memory(
                              _pending[i],
                              width: 58,
                              height: 58,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            right: 0,
                            top: 0,
                            child: GestureDetector(
                              onTap: () => setState(() => _pending.removeAt(i)),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close,
                                  size: 16,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                )
              : const SizedBox.shrink(),
          SafeArea(
            top: false,
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: cs.outlineVariant, width: 0.5),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    onPressed: (_sending || _compressing) ? null : _pickImages,
                    icon: const Icon(Icons.image_outlined),
                    tooltip: Lc.current.addImage,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 6,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: Lc.current.saySomething,
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                    tooltip: Lc.current.send,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _msgArea(BuildContext context) {
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
                _load(initial: true);
              },
              child: Text(Lc.current.retry),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      itemCount: _msgs.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, i) {
        if (_hasMore && i == 0) {
          return TextButton(
            onPressed: _loadEarlier,
            child: Text(Lc.current.dmEarlier),
          );
        }
        final m = _msgs[_hasMore ? i - 1 : i];
        final mine = (m['from_id'] ?? 0) == AppState.instance.user?['id'];
        final body = (m['body'] ?? '') as String;
        final imgs = (m['images'] as List? ?? const []).cast<String>();
        return Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.72,
            ),
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: mine ? cs.primaryContainer : cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: mine
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                if (imgs.isNotEmpty)
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (final u in imgs)
                        GestureDetector(
                          onTap: () => showDialog(
                            context: context,
                            builder: (_) => Dialog(
                              backgroundColor: Colors.transparent,
                              child: InteractiveViewer(
                                child: Image.network(Api.img(u)),
                              ),
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              Api.img(u),
                              width: 120,
                              height: 120,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                    ],
                  ),
                if (body.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(top: imgs.isEmpty ? 0 : 6),
                    child: SelectableText(
                      body,
                      style: TextStyle(
                        color: mine ? cs.onPrimaryContainer : cs.onSurface,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
