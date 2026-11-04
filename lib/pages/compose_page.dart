import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' hide PickedFile;
import 'package:shared_preferences/shared_preferences.dart';

import '../api.dart';
import '../plat.dart';
import '../sites.dart';
import '../store.dart';
import '../draft_images.dart';
import '../file_pick.dart';
import '../img_compress.dart';
import '../widgets/file_card.dart';
import '../widgets/mention.dart';
import 'gallery_picker_page.dart';

import '../l10n/error_text.dart';
import '../l10n/l10n.dart';
import '../widgets/toast.dart';
import '../cloud.dart';
import '../file_browser.dart';
import 'cloud_pick_page.dart';

/// 发主题帖。
///
/// 站内只有一层：发到主站还是小站，选完就直接发，没有板块可选。
/// 草稿只留一份，跟选哪座站无关。
const String _draftKey = 'site';

class ComposePage extends StatefulWidget {
  const ComposePage({super.key});

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
  final List<PostFile> _files = [];
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

  /// 发到哪座站：null = 跟着当前站走。
  String? _targetKey;

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

  /// 可选的去处：主站排最前，小站跟在后面。
  ///
  /// 一张站点表都没有（自编译的空表、或者还没配站）就只发到当前站，
  /// 界面不显示这排选择，别让发帖跟着卡住。
  List<SiteEntry> get _targets {
    final home = <SiteEntry>[];
    final rest = <SiteEntry>[];
    for (final s in AppState.instance.sites) {
      if (!s.valid) continue;
      (s.isHome ? home : rest).add(s);
    }
    return [...home, ...rest];
  }

  /// 选中的那座站。没选过就跟着当前站，再不行落到第一座。
  SiteEntry? get _target {
    final list = _targets;
    if (list.isEmpty) return null;
    final key = _targetKey;
    if (key != null) {
      for (final s in list) {
        if (s.key == key) return s;
      }
    }
    final active = AppState.instance.activeSite;
    for (final s in list) {
      if (s.key == active?.key) return s;
    }
    return list.first;
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
      _draftKey,
      _title.text,
      _body.text,
      imgs: needImgs ? _imgs.map((e) => e.bytes).toList() : null,
    );
  }

  Future<void> _loadDraft() async {
    final d = await Draft.read(_draftKey);
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
      imgs.isEmpty
          ? Lc.current.resumeDraft
          : Lc.current.resumeDraftImages('${imgs.length}'),
      action: SnackBarAction(
        label: Lc.current.discardDraft,
        onPressed: () {
          _draftTimer?.cancel();
          _savedImgSig = '';
          Draft.clear(_draftKey);
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
    toast(context, m, action: action);
  }

  // ── 图片 ───────────────────────────────────────────────

  Future<void> _pickSheet() async {
    if (_busy || _compressing) return;
    if (_imgs.length >= _maxImgs) {
      _snack(Lc.current.maxImages('$_maxImgs'));
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
              title: Text(Lc.current.pickFromAlbum),
              subtitle: Text(Lc.current.canAddMore('${left}')),
              onTap: () => Navigator.of(c).pop('album'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(Lc.current.takePhoto),
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

  /// 挑一个附件，选中就传。传完只留服务端给的地址/名字/大小。
  Future<void> _pickFile() async {
    if (_files.length >= 5) {
      _snack(Lc.current.attachMax('5'));
      return;
    }
    final left = 5 - _files.length;
    final src = await _fileSource();
    if (!mounted || src == null) return;
    if (src == 'cloud') {
      await _addFromCloud(left);
      return;
    }
    await _pickFromDevice(left);
  }

  /// 设备上的文件。手机用自己写的浏览器翻，桌面和网页退到系统选择器
  /// ——那边没有「应用能随便读盘」这回事。
  Future<void> _pickFromDevice(int left) async {
    if (fileBrowserSupported) {
      final picked = await Navigator.of(context).push<List<PickedFile>>(
        MaterialPageRoute(
          builder: (_) => const FileBrowserPage(pickOnly: true),
        ),
      );
      if (!mounted || picked == null || picked.isEmpty) return;
      await _uploadPicked(picked.take(left).toList());
      return;
    }
    final f = await pickFile();
    if (f == null || !mounted) return;
    await _uploadPicked([f]);
  }

  Future<void> _uploadPicked(List<PickedFile> list) async {
    for (final f in list) {
      if (f.size > 500 * 1024 * 1024) {
        _snack(Lc.current.attachTooBig('500MB'));
        continue;
      }
      setState(() {
        _busy = true;
        _status = Lc.current.attachUploading(f.name);
        _progress = 0;
      });
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
        _fail(e);
        return;
      } finally {
        if (mounted) {
          setState(() {
            _busy = false;
            _status = '';
            _progress = 0;
          });
        }
      }
    }
  }

  /// 附件从哪来：云盘里现成的，还是设备上挑一个新的。
  /// 云盘的不用再传一遍，地址直接能用。
  Future<String?> _fileSource() {
    return showModalBottomSheet<String>(
      context: context,
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

  Future<void> _addFromCloud(int left) async {
    final picked = await Navigator.of(context).push<List<CloudFile>>(
      MaterialPageRoute(builder: (_) => CloudPickPage(maxCount: left)),
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    setState(() {
      for (final f in picked.take(left)) {
        _files.add(PostFile(url: f.url, name: f.name, size: f.size));
      }
    });
  }

  Future<void> _pickSystem() async {
    try {
      final picked = await _picker.pickMultiImage();
      if (picked.isEmpty) return;
      await _ingest(picked);
    } catch (e) {
      _snack(Lc.current.albumFailed('$e'));
    }
  }

  Future<void> _pickCamera() async {
    try {
      final one = await _picker.pickImage(source: ImageSource.camera);
      if (one == null) return;
      await _ingest([one]);
    } catch (e) {
      _snack(Lc.current.cameraFailed('${e}'));
    }
  }

  /// 收下选中的图：按剩余名额截断，逐张压缩后进预览条。
  Future<void> _ingest(List<XFile> picked) async {
    final room = _maxImgs - _imgs.length;
    if (room <= 0) {
      _snack(Lc.current.maxImages('$_maxImgs'));
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
          _snack(Lc.current.imageStillTooBig);
        } else {
          _imgs.add(_PendingImg.next(b));
        }
        if (mounted) setState(() => _compressDone++);
      }
      if (picked.length > room) _snack(Lc.current.tooManyImages('${_maxImgs}'));
    } catch (e) {
      _snack(Lc.current.readImageFailed('$e'));
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
                  tooltip: Lc.current.deleteThisImage,
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
      _imgs.isNotEmpty ||
      _files.isNotEmpty;

  bool get _canSubmit =>
      _title.text.trim().isNotEmpty &&
      (_body.text.trim().isNotEmpty || _imgs.isNotEmpty || _files.isNotEmpty);

  Future<void> _submit() async {
    if (_busy || !_canSubmit) return;
    final t = _title.text.trim();
    final b = _body.text.trim();
    // 选了别的站就先切过去再发：图和帖子都落在同一座站上，
    // 不会出现「图片传在这边、帖子在那边」。
    final target = _target;
    if (target != null && target.key != AppState.instance.activeKey) {
      setState(() {
        _busy = true;
        _status = Lc.current.siteSwitching(target.display);
      });
      final ok = await AppState.instance.switchSite(target);
      if (!mounted) return;
      if (!ok) {
        _fail(Lc.current.connectFailed(target.display));
        return;
      }
    }
    final total = _imgs.length + 1;
    setState(() {
      _busy = true;
      _progress = 0;
      _status = _imgs.isEmpty
          ? Lc.current.publishing
          : Lc.current.uploadingStart('${_imgs.length}');
    });
    try {
      final urls = <String>[];
      for (var i = 0; i < _imgs.length; i++) {
        if (mounted) {
          setState(() {
            _status = Lc.current.uploadingImages('${i + 1}', '${_imgs.length}');
            _progress = i / total;
          });
        }
        urls.add(await Api.uploadImage(_imgs[i].bytes));
      }
      if (mounted) {
        setState(() {
          _status = Lc.current.publishing;
          _progress = _imgs.length / total;
        });
      }
      await Api.post('/threads', {
        'title': t,
        'body': b,
        'images': urls,
        'files': _files.map((f) => f.toJson()).toList(),
      });
      _draftTimer?.cancel();
      await Draft.clear(_draftKey);
      if (!mounted) return;
      _posted = true;
      setState(() => _progress = 1);
      await _leaveAfter(true);
    } on ApiException catch (e) {
      _fail(e);
    } catch (e) {
      _fail(Lc.current.postFailed('${e}'));
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
            ListTile(
              dense: true,
              title: Text(Lc.current.draftUnsaved),
              subtitle: Text(Lc.current.draftImagesNote),
            ),
            ListTile(
              leading: const Icon(Icons.save_outlined),
              title: Text(Lc.current.saveDraftAndLeave),
              onTap: () => Navigator.of(c).pop('draft'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(Lc.current.discardPost),
              onTap: () => Navigator.of(c).pop('discard'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(Lc.current.keepEditing),
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
        await Draft.clear(_draftKey);
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
        appBar: AppBar(title: Text(Lc.current.composeTitle)),
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusScope.of(context).unfocus(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              if (_targets.isNotEmpty) ...[
                _siteRow(cs),
                const SizedBox(height: 12),
              ],
              _titleBox(cs),
              const SizedBox(height: 12),
              _bodyBox(cs),
              if (_imgs.isNotEmpty) ...[
                const SizedBox(height: 20),
                _imagesHeader(cs),
                const SizedBox(height: 10),
                _imagesStrip(cs),
              ],
              if (_files.isNotEmpty) ...[
                const SizedBox(height: 16),
                EditableFileCards(
                  files: _files,
                  busy: _busy,
                  onRemove: (f) => setState(() => _files.remove(f)),
                ),
              ],
            ],
          ),
        ),
        bottomNavigationBar: _bottomBar(cs),
      ),
    );
  }

  /// 发到哪座站。横着排，点一下换一个：主站 / 小站，就这两类。
  Widget _siteRow(ColorScheme cs) {
    final l = Lc.current;
    final list = _targets;
    final small = list.where((s) => !s.isHome).length;
    final picked = _target;
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8, left: 2),
            child: Center(
              child: Text(
                l.sitePostTo,
                style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
              ),
            ),
          ),
          for (final s in list)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(
                  s.isHome
                      ? l.siteMaster
                      // 小站多于一座时得带上名字，否则分不出是哪个
                      : (small > 1
                            ? '${l.siteSmall} · ${s.display}'
                            : l.siteSmall),
                ),
                selected: picked?.key == s.key,
                onSelected: (_) => setState(() => _targetKey = s.key),
              ),
            ),
        ],
      ),
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
      decoration: _fieldDeco(cs, hint: Lc.current.title).copyWith(
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
          decoration: _fieldDeco(cs, hint: Lc.current.composeHint),
        ),
      ],
    );
  }

  Widget _imagesHeader(ColorScheme cs) {
    return Row(
      children: [
        Text(
          Lc.current.imageCount('${_imgs.length}', '${_maxImgs}'),
          style: TextStyle(
            fontSize: 12,
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        if (_imgs.length > 1)
          Text(
            Lc.current.dragToReorder,
            style: TextStyle(fontSize: 11, color: cs.outline),
          ),
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
                      tooltip: Lc.current.addImageShort,
                    ),
                    const SizedBox(width: 6),
                    IconButton.filledTonal(
                      onPressed: (_busy || _compressing) ? null : _pickFile,
                      icon: const Icon(Icons.attach_file),
                      tooltip: Lc.current.attachFile,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _busy
                            ? _status
                            : _imgs.isEmpty
                            ? Lc.current.titleRequiredMaxImages('${_maxImgs}')
                            : Lc.current.imageCountPrefix(
                                '${_imgs.length}',
                                '${_maxImgs}',
                                '${ImgCompress.kb(_imgs.fold(0, (a, b) => a + b.bytes.length))}',
                              ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, color: cs.outline),
                      ),
                    ),
                    if (bodyLen > 0)
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: Text(
                          Lc.current.bodyLength('${bodyLen}'),
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
                          : Text(Lc.current.publish),
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

/// 发帖草稿，只有一份。
class Draft {
  static const _k = 'draft_v1';

  /// 文字在 prefs，图片在文件目录；返回 null 表示没有草稿。
  static Future<Map<String, dynamic>?> read(String slot) async {
    final prefs = await SharedPreferencesHolder.prefs;
    final raw = prefs.getString('$_k::$slot');
    final imgs = await loadDraftImages(slot);
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
    String slot,
    String title,
    String body, {
    List<Uint8List>? imgs,
  }) async {
    final prefs = await SharedPreferencesHolder.prefs;
    if (title.isEmpty && body.isEmpty && (imgs == null || imgs.isEmpty)) {
      await prefs.remove('$_k::$slot');
      await clearDraftImages(slot);
      return;
    }
    await prefs.setString('$_k::$slot', '$title\u0001$body');
    if (imgs != null) await saveDraftImages(slot, imgs);
  }

  static Future<void> clear(String slot) async {
    final prefs = await SharedPreferencesHolder.prefs;
    await prefs.remove('$_k::$slot');
    await clearDraftImages(slot);
  }
}

/// 轻量的 SharedPreferences 复用，避免每处都 getInstance()。
class SharedPreferencesHolder {
  static Future<SharedPreferences>? _f;

  static Future<SharedPreferences> get prefs =>
      _f ??= SharedPreferences.getInstance();
}
