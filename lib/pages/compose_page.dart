import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api.dart';
import '../plat.dart';
import '../draft_images.dart';
import '../img_compress.dart';
import '../widgets/mention.dart';
import 'gallery_picker_page.dart';

import '../l10n/error_text.dart';
/// 发主题帖。
class ComposePage extends StatefulWidget {
  final String forumName;
  final String forumTitle;

  const ComposePage({
    super.key,
    required this.forumName,
    required this.forumTitle,
  });

  @override
  State<ComposePage> createState() => _ComposePageState();
}

/// 选好但还没上传的图片。id 用来给拖拽排序提供稳定 key。
class _PendingImg {
  final int id;
  final Uint8List bytes;
  _PendingImg(this.id, this.bytes);

  static int _seq = 0;
  factory _PendingImg.next(Uint8List b) => _PendingImg(++_seq, b);
}

class _ComposePageState extends State<ComposePage> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final MentionWatcher _mention = MentionWatcher();
  final _bodyFocus = FocusNode();
  final _picker = ImagePicker();
  final List<_PendingImg> _imgs = [];
  Timer? _draftTimer;
  String _savedImgSig = '';

  bool _busy = false;
  bool _compressing = false;
  bool _allowPop = false;
  bool _posted = false;
  double _progress = 0;
  int _compressDone = 0;
  int _compressTotal = 0;
  String _status = '';

  static const _maxImgs = 9;
  static const _titleMax = 120;

  @override
  void initState() {
    super.initState();
    _title.addListener(_onEdit);
    _body.addListener(_onEdit);
    _body.addListener(_onMention);
    _loadDraft();
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    if (!_posted) _saveDraft();
    _title.dispose();
    _body.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  void _onEdit() {
    if (mounted) setState(() {});
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 600), () => _saveDraft());
  }

  /// 文字每次都写，图只在增删排序后写一次。
  Future<void> _saveDraft() {
    final sig = _imgs.map((e) => e.id).join(',');
    final needImgs = sig != _savedImgSig;
    _savedImgSig = sig;
    return Draft.write(
      widget.forumName,
      _title.text,
      _body.text,
      imgs: needImgs ? _imgs.map((e) => e.bytes).toList() : null,
    );
  }

  Future<void> _loadDraft() async {
    final d = await Draft.read(widget.forumName);
    if (d == null || !mounted) return;
    if (_title.text.isNotEmpty || _body.text.isNotEmpty) return;
    if (_imgs.isNotEmpty) return;
    final imgs = ((d['images'] as List?) ?? const []).cast<Uint8List>();
    setState(() {
      _title.text = d['title'] ?? '';
      _body.text = d['body'] ?? '';
      for (final b in imgs.take(_maxImgs)) {
        _imgs.add(_PendingImg.next(b));
      }
      _savedImgSig = _imgs.map((e) => e.id).join(',');
    });
    _snack(
      imgs.isEmpty ? '接着上次的写' : '接着上次的写，带 ${imgs.length} 张图',
      action: SnackBarAction(
        label: '清掉',
        onPressed: () {
          _draftTimer?.cancel();
          _savedImgSig = '';
          Draft.clear(widget.forumName);
          setState(() {
            _title.clear();
            _body.clear();
            _imgs.clear();
          });
        },
      ),
    );
  }

  void _snack(String m, {SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(m), action: action));
  }

  // ── 图片 ───────────────────────────────────────────────

  Future<void> _pickSheet() async {
    if (_busy || _compressing) return;
    if (_imgs.length >= _maxImgs) {
      _snack('最多 $_maxImgs 张');
      return;
    }
    final left = _maxImgs - _imgs.length;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('从相册选'),
              subtitle: Text('还能加 $left 张'),
              onTap: () => Navigator.of(c).pop('album'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('拍一张'),
              onTap: () => Navigator.of(c).pop('camera'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == 'album') {
      await _pickOwn(left);
    } else if (choice == 'camera') {
      await _pickCamera();
    }
  }

  /// 自己的相册页。网页版没有 MediaStore，退回系统的文件选择。
  Future<void> _pickOwn(int left) async {
    if (!hasMediaStore) {
      await _pickSystem();
      return;
    }
    final chosen = await pickOwnGallery(context, maxCount: left);
    if (chosen.isEmpty) return;
    await _ingest(chosen);
  }

  Future<void> _pickSystem() async {
    try {
      final picked = await _picker.pickMultiImage();
      if (picked.isEmpty) return;
      await _ingest(picked);
    } catch (e) {
      _snack('打不开相册：$e');
    }
  }

  Future<void> _pickCamera() async {
    try {
      final one = await _picker.pickImage(source: ImageSource.camera);
      if (one == null) return;
      await _ingest([one]);
    } catch (e) {
      _snack('打不开相机：$e');
    }
  }

  /// 收下选中的图：按剩余名额截断，逐张压缩后进预览条。
  Future<void> _ingest(List<XFile> picked) async {
    final room = _maxImgs - _imgs.length;
    if (room <= 0) {
      _snack('最多 $_maxImgs 张');
      return;
    }
    final take = picked.take(room).toList();
    setState(() {
      _compressing = true;
      _compressDone = 0;
      _compressTotal = take.length;
    });
    try {
      for (final x in take) {
        final raw = await x.readAsBytes();
        final b = await ImgCompress.run(raw);
        if (ImgCompress.tooBig(b)) {
          _snack('有张图压完还是太大，跳过了');
        } else {
          _imgs.add(_PendingImg.next(b));
        }
        if (mounted) setState(() => _compressDone++);
      }
      if (picked.length > room) _snack('最多 $_maxImgs 张，多的没收');
    } catch (e) {
      _snack('读图失败：$e');
    } finally {
      if (mounted) {
        setState(() {
          _compressing = false;
          _compressDone = 0;
          _compressTotal = 0;
        });
      }
    }
  }

  void _onReorder(int oldIndex, int newIndex) {
    if (oldIndex >= _imgs.length) return;
    setState(() {
      final to = newIndex.clamp(0, _imgs.length - 1);
      _imgs.insert(to, _imgs.removeAt(oldIndex));
    });
  }

  Future<void> _preview(int start) async {
    var current = start;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black,
      builder: (c) => StatefulBuilder(
        builder: (c, setLocal) => Stack(
          children: [
            PageView.builder(
              controller: PageController(initialPage: start),
              itemCount: _imgs.length,
              onPageChanged: (v) => current = v,
              itemBuilder: (_, i) => GestureDetector(
                onTap: () => Navigator.of(c).pop(),
                child: InteractiveViewer(
                  maxScale: 4,
                  child: Center(
                    child: Image.memory(_imgs[i].bytes, fit: BoxFit.contain),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 8,
              top: 8,
              child: SafeArea(
                child: IconButton(
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black45,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(c).pop(),
                ),
              ),
            ),
            Positioned(
              right: 8,
              top: 8,
              child: SafeArea(
                child: IconButton(
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black45,
                    foregroundColor: Colors.white,
                  ),
                  tooltip: '删掉这张',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () {
                    setState(() => _imgs.removeAt(current));
                    setLocal(() {});
                    if (_imgs.isEmpty) Navigator.of(c).pop();
                  },
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 4,
              child: SafeArea(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${current + 1} / ${_imgs.length}',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  // ── 发布 / 离开 ─────────────────────────────────────────

  bool get _hasContent =>
      _title.text.trim().isNotEmpty ||
      _body.text.trim().isNotEmpty ||
      _imgs.isNotEmpty;

  bool get _canSubmit =>
      _title.text.trim().isNotEmpty &&
      (_body.text.trim().isNotEmpty || _imgs.isNotEmpty);

  Future<void> _submit() async {
    if (_busy || !_canSubmit) return;
    final t = _title.text.trim();
    final b = _body.text.trim();
    final total = _imgs.length + 1;
    setState(() {
      _busy = true;
      _progress = 0;
      _status = _imgs.isEmpty ? '发布中…' : '上传图片 0/${_imgs.length}';
    });
    try {
      final urls = <String>[];
      for (var i = 0; i < _imgs.length; i++) {
        if (mounted) {
          setState(() {
            _status = '上传图片 ${i + 1}/${_imgs.length}';
            _progress = i / total;
          });
        }
        urls.add(await Api.uploadImage(_imgs[i].bytes));
      }
      if (mounted) {
        setState(() {
          _status = '发布中…';
          _progress = _imgs.length / total;
        });
      }
      await Api.post('/f/${Uri.encodeComponent(widget.forumName)}/threads', {
        'title': t,
        'body': b,
        'images': urls,
      });
      _draftTimer?.cancel();
      await Draft.clear(widget.forumName);
      if (!mounted) return;
      _posted = true;
      setState(() => _progress = 1);
      await _leaveAfter(true);
    } on ApiException catch (e) {
      _fail(e);
    } catch (e) {
      _fail('发不出去：$e');
    }
  }

  void _fail(Object msg) {
    if (!mounted) return;
    final text = msg is String ? msg : errorText(context, msg);
    setState(() {
      _busy = false;
      _progress = 0;
      _status = '';
    });
    _snack(text);
  }

  /// PopScope 拦住之后，要先把 canPop 放开、等一帧再 pop，不然又被拦回来。
  Future<void> _leaveAfter([Object? result]) async {
    setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop(result);
  }

  Future<void> _handleBack() async {
    if (_busy) return;
    if (!_hasContent) {
      await _leaveAfter();
      return;
    }
    final act = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              dense: true,
              title: Text('这篇还没发出去'),
              subtitle: Text('图片不进草稿，只有标题和正文会留着'),
            ),
            ListTile(
              leading: const Icon(Icons.save_outlined),
              title: const Text('存草稿，先走'),
              onTap: () => Navigator.of(c).pop('draft'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('扔掉这篇'),
              onTap: () => Navigator.of(c).pop('discard'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('再改改'),
              onTap: () => Navigator.of(c).pop(),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (act) {
      case 'draft':
        _draftTimer?.cancel();
        _savedImgSig = '';
        await _saveDraft();
        await _leaveAfter();
      case 'discard':
        _draftTimer?.cancel();
        await Draft.clear(widget.forumName);
        _imgs.clear();
        _title.clear();
        _body.clear();
        await _leaveAfter();
      default:
        break;
    }
  }

  // ── 界面 ───────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('发新帖')),
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusScope.of(context).unfocus(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              _forumLine(cs),
              const SizedBox(height: 14),
              _titleBox(cs),
              const SizedBox(height: 12),
              _bodyBox(cs),
              if (_imgs.isNotEmpty) ...[
                const SizedBox(height: 20),
                _imagesHeader(cs),
                const SizedBox(height: 10),
                _imagesStrip(cs),
              ],
            ],
          ),
        ),
        bottomNavigationBar: _bottomBar(cs),
      ),
    );
  }

  Widget _forumLine(ColorScheme cs) {
    return Row(
      children: [
        Icon(Icons.tag, size: 14, color: cs.primary),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            widget.forumTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              color: cs.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text('吧', style: TextStyle(fontSize: 12.5, color: cs.outline)),
      ],
    );
  }

  InputDecoration _fieldDeco(ColorScheme cs, {String? hint}) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.42),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: cs.primary.withValues(alpha: 0.6)),
      ),
      counterText: '',
    );
  }

  Widget _titleBox(ColorScheme cs) {
    final n = _title.text.length;
    return TextField(
      controller: _title,
      maxLength: _titleMax,
      textInputAction: TextInputAction.next,
      onSubmitted: (_) => _bodyFocus.requestFocus(),
      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      decoration: _fieldDeco(cs, hint: '标题').copyWith(
        suffixText: n >= 90 ? '$n/$_titleMax' : null,
        suffixStyle: TextStyle(
          fontSize: 11,
          color: n >= _titleMax ? cs.error : cs.outline,
        ),
      ),
    );
  }

  void _onMention() => _mention.scan(_body);

  Widget _bodyBox(ColorScheme cs) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MentionStrip(watcher: _mention, controller: _body),
        TextField(
          controller: _body,
          focusNode: _bodyFocus,
          minLines: 7,
          maxLines: null,
          maxLength: 20000,
          keyboardType: TextInputType.multiline,
          style: const TextStyle(fontSize: 15, height: 1.55),
          decoration: _fieldDeco(cs, hint: '说点什么…（@ 找人）'),
        ),
      ],
    );
  }

  Widget _imagesHeader(ColorScheme cs) {
    return Row(
      children: [
        Text(
          '图片 ${_imgs.length}/$_maxImgs',
          style: TextStyle(
            fontSize: 12,
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        if (_imgs.length > 1)
          Text('长按拖动换顺序', style: TextStyle(fontSize: 11, color: cs.outline)),
      ],
    );
  }

  Widget _imagesStrip(ColorScheme cs) {
    return SizedBox(
      height: 88,
      child: ReorderableListView.builder(
        scrollDirection: Axis.horizontal,
        buildDefaultDragHandles: false,
        itemCount: _imgs.length + (_imgs.length < _maxImgs ? 1 : 0),
        onReorderItem: _onReorder,
        proxyDecorator: (child, i, anim) => Material(
          color: Colors.transparent,
          elevation: 6,
          borderRadius: BorderRadius.circular(10),
          child: child,
        ),
        itemBuilder: (c, i) {
          if (i == _imgs.length) return _addTile(cs);
          final img = _imgs[i];
          return ReorderableDelayedDragStartListener(
            key: ValueKey(img.id),
            index: i,
            child: Padding(
              padding: const EdgeInsets.only(top: 4, right: 8),
              child: _thumb(cs, img, i),
            ),
          );
        },
      ),
    );
  }

  Widget _thumb(ColorScheme cs, _PendingImg img, int i) {
    return GestureDetector(
      onTap: () => _preview(i),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.memory(
              img.bytes,
              width: 76,
              height: 76,
              fit: BoxFit.cover,
              gaplessPlayback: true,
            ),
          ),
          Positioned(
            right: -3,
            top: -3,
            child: GestureDetector(
              onTap: () => setState(() => _imgs.removeAt(i)),
              child: Container(
                decoration: BoxDecoration(
                  color: cs.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: cs.outlineVariant, width: 0.5),
                ),
                padding: const EdgeInsets.all(1.5),
                child: Icon(Icons.close, size: 12, color: cs.onSurface),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _addTile(ColorScheme cs) {
    return Padding(
      key: const ValueKey('add-tile'),
      padding: const EdgeInsets.only(top: 4, right: 8),
      child: GestureDetector(
        onTap: _compressing ? null : _pickSheet,
        child: Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: _compressing
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        value: _compressTotal == 0
                            ? null
                            : _compressDone / _compressTotal,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '$_compressDone/$_compressTotal',
                      style: TextStyle(fontSize: 10, color: cs.outline),
                    ),
                  ],
                )
              : Icon(
                  Icons.add_photo_alternate_outlined,
                  size: 22,
                  color: cs.primary,
                ),
        ),
      ),
    );
  }

  Widget _bottomBar(ColorScheme cs) {
    final bodyLen = _body.text.trim().length;
    return Material(
      color: cs.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_busy)
            LinearProgressIndicator(
              value: _progress == 0 ? null : _progress,
              minHeight: 2,
            ),
          Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: _busy
                      ? Colors.transparent
                      : cs.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
                child: Row(
                  children: [
                    IconButton.filledTonal(
                      onPressed: (_busy || _compressing) ? null : _pickSheet,
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      tooltip: '加图',
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _busy
                            ? _status
                            : _imgs.isEmpty
                            ? '标题必填 · 最多 $_maxImgs 张图'
                            : '${_imgs.length}/$_maxImgs 张 · '
                                  '${ImgCompress.kb(_imgs.fold(0, (a, b) => a + b.bytes.length))}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, color: cs.outline),
                      ),
                    ),
                    if (bodyLen > 0)
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: Text(
                          '$bodyLen 字',
                          style: TextStyle(fontSize: 11.5, color: cs.outline),
                        ),
                      ),
                    FilledButton(
                      onPressed: (_busy || !_canSubmit) ? null : _submit,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(84, 42),
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        textStyle: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: _busy
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: cs.onPrimary,
                              ),
                            )
                          : const Text('发布'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 发帖草稿，按吧分开存。
class Draft {
  static const _k = 'draft_v1';

  /// 文字在 prefs，图片在文件目录；返回 null 表示没有草稿。
  static Future<Map<String, dynamic>?> read(String forum) async {
    final prefs = await SharedPreferencesHolder.prefs;
    final raw = prefs.getString('$_k::$forum');
    final imgs = await loadDraftImages(forum);
    if (raw == null || raw.isEmpty) {
      if (imgs.isEmpty) return null;
      return {'title': '', 'body': '', 'images': imgs};
    }
    final parts = raw.split('\u0001');
    return {
      'title': parts.isNotEmpty ? parts[0] : '',
      'body': parts.length > 1 ? parts[1] : '',
      'images': imgs,
    };
  }

  static Future<void> write(
    String forum,
    String title,
    String body, {
    List<Uint8List>? imgs,
  }) async {
    final prefs = await SharedPreferencesHolder.prefs;
    if (title.isEmpty && body.isEmpty && (imgs == null || imgs.isEmpty)) {
      await prefs.remove('$_k::$forum');
      await clearDraftImages(forum);
      return;
    }
    await prefs.setString('$_k::$forum', '$title\u0001$body');
    if (imgs != null) await saveDraftImages(forum, imgs);
  }

  static Future<void> clear(String forum) async {
    final prefs = await SharedPreferencesHolder.prefs;
    await prefs.remove('$_k::$forum');
    await clearDraftImages(forum);
  }
}

/// 轻量的 SharedPreferences 复用，避免每处都 getInstance()。
class SharedPreferencesHolder {
  static Future<SharedPreferences>? _f;

  static Future<SharedPreferences> get prefs =>
      _f ??= SharedPreferences.getInstance();
}
