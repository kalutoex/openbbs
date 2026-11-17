import 'package:flutter/material.dart';

import '../downloads.dart' show sizeText;
import '../manga_download.dart';
import '../widgets/toast.dart';

/// 传输页里的「漫画」一段：正在下的几本 + 本机存着的几本。
///
/// 跟论坛附件那套分开摆：那些是单个文件，这些是一本一本的书，
/// 一个进度条背后是几十话几百张图。
class MangaDlSection extends StatelessWidget {
  const MangaDlSection({super.key});

  @override
  Widget build(BuildContext context) {
    if (!MangaDown.i.supported) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: MangaDown.i,
      builder: (context, _) {
        final jobs = MangaDown.i.jobs;
        final books = MangaDown.i.offlineBooks;
        if (jobs.isEmpty && books.isEmpty) return const SizedBox.shrink();
        final cs = Theme.of(context).colorScheme;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
              child: Row(
                children: [
                  Text(
                    '漫画',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  if (books.isNotEmpty)
                    Text(
                      '本机 ${books.length} 本',
                      style: TextStyle(fontSize: 11.5, color: cs.outline),
                    ),
                ],
              ),
            ),
            for (final j in jobs) _jobRow(context, j),
            for (final b in books.take(6)) _bookRow(context, b),
            if (books.length > 6)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: Text(
                  '还有 ${books.length - 6} 本，去书架长按多选删',
                  style: TextStyle(fontSize: 11.5, color: cs.outline),
                ),
              ),
            const SizedBox(height: 4),
            Divider(height: 1, indent: 16, endIndent: 16, color: cs.outlineVariant),
            const SizedBox(height: 4),
          ],
        );
      },
    );
  }

  Widget _jobRow(BuildContext context, MangaDlJob j) {
    final cs = Theme.of(context).colorScheme;
    final pct = (j.progress * 100).round();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      child: Row(
        children: [
          Icon(Icons.auto_stories, size: 22, color: cs.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  j.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: j.progress > 0 ? j.progress : null,
                    minHeight: 3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${j.chaptersDone}/${j.chaptersTotal} 话 · $pct%',
                  style: TextStyle(fontSize: 11.5, color: cs.outline),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '取消',
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => MangaDown.i.cancelBook(j.dir),
          ),
        ],
      ),
    );
  }

  Widget _bookRow(BuildContext context, MangaDlBook b) {
    final cs = Theme.of(context).colorScheme;
    final size = sizeText(b.bytes);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 8, 2),
      child: Row(
        children: [
          Icon(Icons.offline_pin_outlined, size: 20, color: cs.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              b.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13.5),
            ),
          ),
          Text(
            '${b.chapters.length} 话 · $size',
            style: TextStyle(fontSize: 11.5, color: cs.outline),
          ),
          IconButton(
            tooltip: '删除这本的离线文件',
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: () => _confirmDelete(context, b),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, MangaDlBook b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删掉《${b.title}》的离线文件？'),
        content: const Text('只删手机里这份，书还在服务器上，随时能再下。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('算了'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await MangaDown.i.deleteBook(b.dir);
    if (context.mounted) toastOf(context, '已删掉《${b.title}》的离线文件');
  }
}
