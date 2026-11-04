import 'package:flutter/material.dart';

import '../api.dart';
import '../file_open.dart';
import '../l10n/error_text.dart';

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
      out.add(PostFile(
        url: url,
        name: (it['name'] ?? '') as String,
        size: (it['size'] is int) ? it['size'] as int : 0,
      ));
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

IconData _iconFor(String name) {
  final ext = name.contains('.')
      ? name.split('.').last.toLowerCase()
      : '';
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
        children: [
          for (final f in files)
            _FileCard(file: f, onRemove: null),
        ],
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
            _FileCard(
              file: f,
              onRemove: busy ? null : () => onRemove(f),
            ),
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
      await openRemoteFile(url, widget.file.name, onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorText(context, e))),
        );
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
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: widget.onRemove == null ? _open : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Icon(_iconFor(widget.file.name), size: 22,
                    color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.file.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.textTheme.bodyMedium,
                      ),
                      Text(
                        _busy && _progress > 0
                            ? '${(_progress * 100).toStringAsFixed(0)}% · ${widget.file.sizeText}'
                            : widget.file.sizeText,
                        style: t.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (widget.onRemove != null)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: widget.onRemove,
                  )
                else if (_busy)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(Icons.download_outlined,
                      size: 20, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
