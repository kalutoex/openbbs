import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart'
    show ImageRenderMethodForWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api.dart';
import '../img_cache.dart';
import '../plat.dart';
import '../img_compress.dart';
import 'gallery_picker_page.dart';

import '../l10n/error_text.dart';
import '../l10n/l10n.dart';
/// 改自己的帖子：标题、正文、配图。
///
/// 图片分两种：已经传上去的（服务端给的 /img/ 路径，可以摘掉）和这次新选的
/// （本地字节，保存时先传再替换）。保存走 PATCH，不动帖子的 updated_at。
class EditThreadPage extends StatefulWidget {
  final int tid;
  final String title;
  final String body;
  final List<String> images;

  const EditThreadPage({
    super.key,
    required this.tid,
    required this.title,
    required this.body,
    required this.images,
  });

  @override
  State<EditThreadPage> createState() => _EditThreadPageState();
}

class _EditThreadPageState extends State<EditThreadPage> {
  late final _title = TextEditingController(text: widget.title);
  late final _body = TextEditingController(text: widget.body);
  late final List<String> _remote = [...widget.images];
  final List<Uint8List> _added = [];

  final _picker = ImagePicker();
  bool _busy = false;
  String _status = '';

  static const _maxImgs = 9;

  int get _count => _remote.length + _added.length;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  bool get _dirty =>
      _title.text != widget.title ||
      _body.text != widget.body ||
      _remote.length != widget.images.length ||
      _added.isNotEmpty;

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _addImages() async {
    final left = _maxImgs - _count;
    if (left <= 0) {
      _snack(Lc.current.maxImages('$_maxImgs'));
      return;
    }
    List<XFile> picked = const [];
    if (!hasMediaStore) {
      picked = await _picker.pickMultiImage();
    } else {
      picked = await pickOwnGallery(context, maxCount: left);
    }
    if (picked.isEmpty) return;
    setState(() => _busy = true);
    try {
      for (final x in picked.take(left)) {
        final b = await ImgCompress.run(await x.readAsBytes());
        if (ImgCompress.tooBig(b)) {
          _snack(Lc.current.imageStillTooBig);
          continue;
        }
        _added.add(b);
      }
      if (mounted) setState(() {});
    } catch (e) {
      _snack(Lc.current.readImageFailed('$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    final t = _title.text.trim();
    final b = _body.text.trim();
    if (t.isEmpty) {
      _snack(Lc.current.titleEmpty);
      return;
    }
    if (b.isEmpty && _count == 0) {
      _snack(Lc.current.bodyOrImageRequired);
      return;
    }
    setState(() {
      _busy = true;
      _status = _added.isEmpty ? Lc.current.saving : Lc.current.uploadingNewStart('${_added.length}');
    });
    try {
      final urls = [..._remote];
      for (var i = 0; i < _added.length; i++) {
        if (mounted) {
          setState(() => _status = Lc.current.uploadingNewImages('${i + 1}', '${_added.length}'));
        }
        urls.add(await Api.uploadImage(_added[i]));
      }
      if (mounted) setState(() => _status = Lc.current.saving);
      await Api.patch('/t/${widget.tid}', {
        'title': t,
        'body': b,
        'images': urls,
      });
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      _fail(errorText(context, e));
    } catch (e) {
      _fail(Lc.current.saveFailed('${e}'));
    }
  }

  void _fail(String m) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = '';
    });
    _snack(m);
  }

  Future<void> _back() async {
    if (_busy) return;
    if (!_dirty) {
      Navigator.of(context).pop();
      return;
    }
    final act = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(dense: true, title: Text(Lc.current.changesUnsaved)),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(Lc.current.continueEditing),
              onTap: () => Navigator.of(c).pop(),
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: Text(Lc.current.leaveWithoutSaving),
              onTap: () => Navigator.of(c).pop('leave'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (act == 'leave' && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(Lc.current.editPost),
          actions: [
            TextButton(
              onPressed: _busy ? null : _save,
              child: Text(
                Lc.current.save,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: _busy ? null : cs.primary,
                ),
              ),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            TextField(
              controller: _title,
              maxLength: 120,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              decoration: _deco(cs, Lc.current.title),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _body,
              minLines: 7,
              maxLines: null,
              maxLength: 20000,
              keyboardType: TextInputType.multiline,
              style: const TextStyle(fontSize: 15, height: 1.55),
              decoration: _deco(cs, Lc.current.body),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Text(
                  Lc.current.imageCountShort('${_count}', '${_maxImgs}'),
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _busy || _count >= _maxImgs ? null : _addImages,
                  icon: const Icon(
                    Icons.add_photo_alternate_outlined,
                    size: 18,
                  ),
                  label: Text(Lc.current.addImageShort),
                ),
              ],
            ),
            const SizedBox(height: 6),
            _imgsGrid(cs),
            if (_busy) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _status,
                    style: TextStyle(fontSize: 12, color: cs.outline),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  InputDecoration _deco(ColorScheme cs, String hint) => InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.42),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: cs.primary.withValues(alpha: 0.6)),
    ),
    counterText: '',
  );

  Widget _imgsGrid(ColorScheme cs) {
    final n = _count;
    if (n == 0) {
      return Text(Lc.current.noImagesYet, style: TextStyle(fontSize: 12, color: cs.outline));
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: n,
      itemBuilder: (_, i) {
        Widget img;
        if (i < _remote.length) {
          img = CachedNetworkImage(
            cacheManager: ImgCache.manager,
            imageRenderMethodForWeb: ImageRenderMethodForWeb.HttpGet,
            imageUrl: Api.img(_remote[i]),
            fit: BoxFit.cover,
            placeholder: (_, _) => Container(color: cs.surfaceContainerHighest),
            errorWidget: (_, _, _) => Container(
              color: cs.surfaceContainerHighest,
              child: Icon(Icons.broken_image_outlined, color: cs.outline),
            ),
          );
        } else {
          img = Image.memory(_added[i - _remote.length], fit: BoxFit.cover);
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            fit: StackFit.expand,
            children: [
              img,
              Positioned(
                right: 2,
                top: 2,
                child: GestureDetector(
                  onTap: _busy
                      ? null
                      : () => setState(() {
                          if (i < _remote.length) {
                            _remote.removeAt(i);
                          } else {
                            _added.removeAt(i - _remote.length);
                          }
                        }),
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(3),
                    child: const Icon(
                      Icons.close,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
