import 'package:flutter/material.dart';

import '../api.dart';
import '../file_open.dart';
import '../l10n/error_text.dart';
import '../l10n/l10n.dart';
import 'toast.dart';

/// 帖子里的一个附件。服务端给的名字和大小，客户端只负责摆出来。
class PostFile {
  const PostFile({required this.url, required this.name, required this.size});

  final String url;
  final String name;
  final int size;

  static List<PostFile> listOf(dynamic raw) {
    if (raw is! List) return const [];
    final out = <PostFile>[];
    for (final it in raw) {
      if (it is! Map) continue;
      final url = (it['url'] ?? '') as String;
      if (url.isEmpty) continue;
      out.add(
        PostFile(
          url: url,
          name: (it['name'] ?? '') as String,
          size: (it['size'] is int) ? it['size'] as int : 0,
        ),
      );
    }
    return out;
  }

  String get sizeText => size >= 1024 * 1024
      ? '${(size / 1024 / 1024).toStringAsFixed(1)} MB'
      : size >= 1024
      ? '${(size / 1024).toStringAsFixed(0)} KB'
      : '$size B';

  Map<String, dynamic> toJson() => {'url': url, 'name': name, 'size': size};
}

IconData fileIconFor(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  switch (ext) {
    case 'zip':
    case 'rar':
    case '7z':
    case 'tar':
    case 'gz':
    case 'xz':
      return Icons.folder_zip_outlined;
    case 'apk':
    case 'exe':
    case 'msi':
    case 'dmg':
      return Icons.android_outlined;
    case 'pdf':
      return Icons.picture_as_pdf_outlined;
    case 'txt':
    case 'md':
    case 'log':
      return Icons.description_outlined;
    case 'mp4':
    case 'mkv':
    case 'avi':
    case 'mov':
      return Icons.movie_outlined;
    case 'mp3':
    case 'flac':
    case 'wav':
    case 'm4a':
      return Icons.audiotrack_outlined;
  }
  return Icons.insert_drive_file_outlined;
}

/// 附件卡的尺寸。主页和帖子里共用一套，改一处两边都变。
class PostFileCard {
  static const double height = 80;
  static const double maxWidth = 420;
}

/// 帖子里那一排附件卡片。点一下就下载。
class FileCards extends StatelessWidget {
  const FileCards({super.key, required this.files});

  final List<PostFile> files;

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        children: [for (final f in files) _FileCard(file: f, onRemove: null)],
      ),
    );
  }
}

/// 发帖页里已传好的附件，能删。
class EditableFileCards extends StatelessWidget {
  const EditableFileCards({
    super.key,
    required this.files,
    required this.onRemove,
    this.busy = false,
  });

  final List<PostFile> files;
  final void Function(PostFile) onRemove;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        children: [
          for (final f in files)
            _FileCard(file: f, onRemove: busy ? null : () => onRemove(f)),
        ],
      ),
    );
  }
}

class _FileCard extends StatefulWidget {
  const _FileCard({required this.file, required this.onRemove});

  final PostFile file;
  final VoidCallback? onRemove;

  @override
  State<_FileCard> createState() => _FileCardState();
}

class _FileCardState extends State<_FileCard> {
  bool _busy = false;
  double _progress = 0;

  Future<void> _open() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _progress = 0;
    });
    try {
      final url = widget.file.url.startsWith('http')
          ? widget.file.url
          : '${Api.base}${widget.file.url}';
      final saved = await openRemoteFile(
        url,
        widget.file.name,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (mounted) toast(context, Lc.current.savedTo(saved.display));
    } catch (e) {
      if (mounted) {
        toast(context, errorText(context, e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final scheme = t.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: LayoutBuilder(
        builder: (context, cons) {
          final w =
              cons.maxWidth.isFinite && cons.maxWidth < PostFileCard.maxWidth
              ? cons.maxWidth
              : PostFileCard.maxWidth;
          return SizedBox(
            width: w,
            height: PostFileCard.height,
            child: Material(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: widget.onRemove == null ? _open : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      _busy
                          ? const SizedBox(
                              width: 30,
                              height: 30,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                              ),
                            )
                          : Icon(
                              fileIconFor(widget.file.name),
                              size: 30,
                              color: scheme.primary,
                            ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              widget.file.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: t.textTheme.bodyMedium?.copyWith(
                                height: 1.25,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _busy && _progress > 0
                                        ? '${(_progress * 100).toStringAsFixed(0)}% · ${widget.file.sizeText}'
                                        : widget.file.sizeText,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: t.textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                if (widget.onRemove != null)
                                  InkResponse(
                                    onTap: widget.onRemove,
                                    radius: 16,
                                    child: Padding(
                                      padding: const EdgeInsets.all(2),
                                      child: Icon(
                                        Icons.close,
                                        size: 18,
                                        color: scheme.outline,
                                      ),
                                    ),
                                  )
                                else if (!_busy)
                                  Icon(
                                    Icons.download_outlined,
                                    size: 16,
                                    color: scheme.onSurfaceVariant,
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 主页列表里的附件：一张小卡片，点一下直接下载。
///
/// 高 80，宽度铺满可用宽度（桌面上限 420）——固定宽度会把文件名压窄，
/// 长文件名全被截断，反而看不清。
class CompactFiles extends StatefulWidget {
  const CompactFiles({super.key, required this.files});

  final List<PostFile> files;

  @override
  State<CompactFiles> createState() => _CompactFilesState();
}

class _CompactFilesState extends State<CompactFiles> {
  int _busy = -1;
  double _progress = 0;

  static const _maxShown = 2;

  Future<void> _open(PostFile f, int i) async {
    if (_busy >= 0) return;
    setState(() {
      _busy = i;
      _progress = 0;
    });
    try {
      final url = f.url.startsWith('http') ? f.url : '${Api.base}${f.url}';
      final saved = await openRemoteFile(
        url,
        f.name,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (mounted) toast(context, Lc.current.savedTo(saved.display));
    } catch (e) {
      if (mounted) {
        toast(context, errorText(context, e));
      }
    } finally {
      if (mounted) setState(() => _busy = -1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final files = widget.files;
    if (files.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final shown = files.take(_maxShown).toList();
    final rest = files.length - shown.length;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: LayoutBuilder(
        builder: (context, cons) {
          final w =
              cons.maxWidth.isFinite && cons.maxWidth < PostFileCard.maxWidth
              ? cons.maxWidth
              : PostFileCard.maxWidth;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < shown.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                _card(context, shown[i], i, w, scheme, tt),
              ],
              if (rest > 0) ...[
                if (shown.isNotEmpty) const SizedBox(height: 8),
                Container(
                  width: w,
                  height: PostFileCard.height,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '+$rest',
                    style: tt.labelLarge?.copyWith(color: scheme.outline),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _card(
    BuildContext context,
    PostFile f,
    int i,
    double w,
    ColorScheme scheme,
    TextTheme tt,
  ) {
    final busy = _busy == i;
    return SizedBox(
      width: w,
      height: PostFileCard.height,
      child: Material(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: _busy >= 0 ? null : () => _open(f, i),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                busy
                    ? SizedBox(
                        width: 30,
                        height: 30,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          value: _progress > 0 ? _progress : null,
                        ),
                      )
                    : Icon(
                        fileIconFor(f.name),
                        size: 30,
                        color: scheme.primary,
                      ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        f.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodyMedium?.copyWith(
                          color: scheme.onSurface,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              busy && _progress > 0
                                  ? '${(_progress * 100).toStringAsFixed(0)}% · ${f.sizeText}'
                                  : f.sizeText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tt.bodySmall?.copyWith(
                                color: scheme.outline,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.download_outlined,
                            size: 15,
                            color: scheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
