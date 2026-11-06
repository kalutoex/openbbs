import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:photo_manager/photo_manager.dart';

import '../plat.dart';
import '../widgets/page_width.dart';

import '../l10n/l10n.dart';
import '../widgets/empty_view.dart';
import '../widgets/toast.dart';

/// 自己的相册页：直接读本机媒体库，缩略图网格 + 多选。
///
/// 用它的原因：系统照片选择器在安卓 13+ 只给「选中的照片」这种受限访问，
/// 相册也拆成「照片 / 合集」两栏，体验不受控。这里拿一次完整读图权限就行。
/// 网页版没有 MediaStore，调用方应跳过这个页面，继续用系统文件选择。
class GalleryPickerPage extends StatefulWidget {
  const GalleryPickerPage({super.key, this.maxCount = 9});

  /// 还能再选几张，由发帖页按剩余名额传进来。
  final int maxCount;

  @override
  State<GalleryPickerPage> createState() => _GalleryPickerPageState();
}

class _GalleryPickerPageState extends State<GalleryPickerPage> {
  final _thumbs = <String, Future<Uint8List?>>{};
  final _selected = <AssetEntity>[];
  final _order = <String>[]; // 选中顺序，用来画右上角的数字

  List<AssetPathEntity> _albums = const [];
  AssetPathEntity? _album;
  List<AssetEntity> _assets = const [];
  bool _loading = true;
  bool _denied = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    if (!hasMediaStore) {
      setState(() {
        _loading = false;
        _denied = true;
      });
      return;
    }
    try {
      final state = await PhotoManager.requestPermissionExtend();
      if (!state.hasAccess) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _denied = true;
        });
        return;
      }
      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        onlyAll: false,
        filterOption: FilterOptionGroup(
          orders: [
            const OrderOption(type: OrderOptionType.createDate, asc: false),
          ],
        ),
      );
      if (!mounted) return;
      if (albums.isEmpty) {
        setState(() {
          _loading = false;
          _albums = albums;
        });
        return;
      }
      // 数量多的排前面，「所有照片」一般就落在第一个
      final counts = <String, int>{};
      for (final a in albums) {
        try {
          counts[a.id] = await a.assetCountAsync;
        } catch (_) {
          counts[a.id] = 0;
        }
      }
      albums.sort((a, b) => (counts[b.id] ?? 0).compareTo(counts[a.id] ?? 0));
      setState(() => _albums = albums);
      await _loadAlbum(albums.first);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _err = Lc.current.galleryReadFailed('$e');
        });
      }
    }
  }

  Future<void> _loadAlbum(AssetPathEntity a) async {
    setState(() {
      _album = a;
      _loading = true;
      _err = null;
    });
    try {
      final list = await a.getAssetListRange(start: 0, end: 600);
      if (!mounted) return;
      setState(() {
        _assets = list;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _err = Lc.current.albumOpenFailed('$e');
        });
      }
    }
  }

  Future<Uint8List?> _thumb(AssetEntity a) {
    return _thumbs.putIfAbsent(
      a.id,
      () => a.thumbnailDataWithSize(const ThumbnailSize(320, 320), quality: 82),
    );
  }

  bool _isPicked(AssetEntity a) => _order.contains(a.id);

  void _toggle(AssetEntity a) {
    if (_isPicked(a)) {
      setState(() {
        _order.remove(a.id);
        _selected.removeWhere((x) => x.id == a.id);
      });
      return;
    }
    if (_selected.length >= widget.maxCount) {
      toast(context, Lc.current.maxSelectImages('${widget.maxCount}'));
      return;
    }
    setState(() {
      _selected.add(a);
      _order.add(a.id);
    });
  }

  Future<void> _preview(AssetEntity a) async {
    final f = await a.file;
    if (f == null || !mounted) return;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black,
      builder: (c) => GestureDetector(
        onTap: () => Navigator.of(c).pop(),
        child: InteractiveViewer(
          maxScale: 4,
          child: Center(child: Image.file(f, fit: BoxFit.contain)),
        ),
      ),
    );
  }

  Future<void> _done() async {
    final out = <XFile>[];
    for (final a in _selected) {
      final f = await a.file;
      if (f != null) {
        out.add(XFile(f.path, name: a.title ?? 'image.jpg'));
        continue;
      }
      // 云端或特殊来源拿不到本地文件，退回原始字节
      final bytes = await a.originBytes;
      if (bytes != null) {
        out.add(XFile.fromData(bytes, name: a.title ?? 'image.jpg'));
      }
    }
    if (!mounted) return;
    Navigator.of(context).pop(out);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(Lc.current.pickPhotos),
        actions: [
          TextButton(
            onPressed: _selected.isEmpty || _loading ? null : _done,
            child: Text(
              _selected.isEmpty
                  ? Lc.current.done
                  : Lc.current.doneWithCount('${_selected.length}'),
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: _selected.isEmpty ? null : cs.primary,
              ),
            ),
          ),
        ],
      ),
      body: PageWidth(child: _body(cs)),
    );
  }

  Widget _body(ColorScheme cs) {
    if (_denied) return _deniedView();
    if (_err != null) return _hint(_err!);
    return Column(
      children: [
        if (_albums.length > 1) _albumBar(cs),
        Expanded(child: _grid(cs)),
      ],
    );
  }

  Widget _albumBar(ColorScheme cs) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        itemCount: _albums.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final a = _albums[i];
          final on = a.id == _album?.id;
          return ChoiceChip(
            label: Text(a.name),
            selected: on,
            showCheckmark: false,
            labelStyle: TextStyle(
              fontSize: 13,
              color: on ? cs.onPrimaryContainer : cs.onSurfaceVariant,
            ),
            selectedColor: cs.primaryContainer,
            onSelected: (_) => _loadAlbum(a),
          );
        },
      ),
    );
  }

  Widget _grid(ColorScheme cs) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_assets.isEmpty) {
      return _hint(Lc.current.albumEmpty);
    }
    return GridView.builder(
      padding: const EdgeInsets.all(3),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 3,
        crossAxisSpacing: 3,
      ),
      itemCount: _assets.length,
      itemBuilder: (_, i) {
        final a = _assets[i];
        final n = _order.indexOf(a.id);
        return GestureDetector(
          onTap: () => _toggle(a),
          onLongPress: () => _preview(a),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(
                color: cs.surfaceContainerHighest,
                child: FutureBuilder<Uint8List?>(
                  future: _thumb(a),
                  builder: (_, s) {
                    final b = s.data;
                    if (b == null) {
                      return s.hasError
                          ? Icon(Icons.broken_image_outlined, color: cs.outline)
                          : const SizedBox.shrink();
                    }
                    return Image.memory(
                      b,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    );
                  },
                ),
              ),
              if (n >= 0)
                Container(
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.28),
                    border: Border.all(color: cs.primary, width: 2),
                  ),
                ),
              Positioned(
                right: 4,
                top: 4,
                child: Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: n >= 0 ? cs.primary : Colors.black26,
                    border: Border.all(color: Colors.white70, width: 1.5),
                  ),
                  child: n >= 0
                      ? Text(
                          '${n + 1}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: cs.onPrimary,
                          ),
                        )
                      : null,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _deniedView() {
    final canUseMedia = hasMediaStore;
    return EmptyView(
      icon: Icons.photo_library_outlined,
      title: canUseMedia
          ? Lc.current.needsAlbumPermission
          : Lc.current.noAlbumUsePicker,
      hint: Lc.current.localThumbsOnly,
      action: FilledButton(
        onPressed: () async {
          if (!canUseMedia) {
            Navigator.of(context).pop(<XFile>[]);
            return;
          }
          final s = await PhotoManager.requestPermissionExtend();
          if (!s.hasAccess) {
            await PhotoManager.openSetting();
            return;
          }
          setState(() => _denied = false);
          await _boot();
        },
        child: Text(
          canUseMedia ? Lc.current.grantPermission : Lc.current.pickAnotherWay,
        ),
      ),
    );
  }

  Widget _hint(String s) =>
      EmptyView(icon: Icons.photo_library_outlined, title: s);
}

/// 打开自己的相册页，返回选中的图。
/// 网页版没有 MediaStore，调用方应继续用系统文件选择。
Future<List<XFile>> pickOwnGallery(
  BuildContext context, {
  int maxCount = 9,
}) async {
  if (!hasMediaStore || maxCount <= 0) return const [];
  final r = await Navigator.of(context).push<List<XFile>>(
    MaterialPageRoute(builder: (_) => GalleryPickerPage(maxCount: maxCount)),
  );
  return r ?? const [];
}
