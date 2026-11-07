import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../cloud.dart';
import '../download_manager.dart';
import '../file_browser.dart';
import '../file_pick.dart';
import '../l10n/error_text.dart';
import '../l10n/l10n.dart';
import '../upload_manager.dart';
import '../utils.dart';
import '../widgets/app_sheet.dart';
import '../widgets/empty_view.dart';
import '../widgets/file_card.dart';
import '../widgets/page_width.dart';
import '../widgets/segmented_pages.dart';
import '../widgets/toast.dart';
import 'cloud_pick_page.dart';
import 'downloads_page.dart';

/// 传输：上传的和已经下到本机的，一个地方看。
///
/// 以前这两样各挂一个按钮在云盘右上角，谁都不在那两页上待着。
class TransfersPage extends StatefulWidget {
  const TransfersPage({super.key});

  @override
  State<TransfersPage> createState() => _TransfersPageState();
}

class _TransfersPageState extends State<TransfersPage> {
  /// 0 = 下载，1 = 上传。下边那个大按钮跟着换。
  int _tab = 0;

  void _toast(String text) {
    if (!mounted) return;
    toast(context, text);
  }

  /// 下载的起点。以前是在云盘里点一下文件就开始下，
  /// 现在云盘只剩看和管理，要取文件就来这儿挑。
  Future<void> _pickToDownload() async {
    final picked = await Navigator.push<List<CloudFile>>(
      context,
      MaterialPageRoute(builder: (_) => const CloudPickPage(maxCount: 20)),
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    for (final f in picked) {
      final key = DownloadManager.keyForCloud(f.id);
      if (DownloadManager.i.isDownloading(key)) continue;
      final url = f.url.startsWith('http') ? f.url : '${Api.base}${f.url}';
      try {
        await DownloadManager.i.start(
          key,
          url,
          f.name,
          total: f.size,
          cloudId: '${f.id}',
        );
      } catch (e) {
        if (!mounted) return;
        _toast(errorText(context, e));
        return;
      }
    }
  }

  /// 上传入口。手机上有内置的文件浏览器，可以翻整个存储；
  /// 别的地方（网页、桌面）还是系统选择器。
  Future<void> _uploadEntry() async {
    if (!fileBrowserSupported) {
      await _upload();
      return;
    }
    final v = await showAppSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: Text(Lc.current.browseFiles),
              subtitle: Text(Lc.current.browseFilesHint),
              onTap: () => Navigator.pop(ctx, 'phone'),
            ),
            ListTile(
              leading: const Icon(Icons.file_open_outlined),
              title: Text(Lc.current.pickFromSystem),
              onTap: () => Navigator.pop(ctx, 'system'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || v == null) return;
    if (v == 'phone') {
      await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => const FileBrowserPage()),
      );
    } else {
      await _upload();
    }
  }

  Future<void> _upload() async {
    final f = await pickFile();
    if (f == null || !mounted) return;
    // 进队列前先自己看一眼额度。服务端也会拦，但那是传了几分钟之后才知道。
    try {
      final u = await CloudApi.usage();
      if (!u.unlimited) {
        // 排在队里的也要算进去，不然一次选十个就都放行了
        var pending = 0;
        for (final j in UploadManager.i.activeJobs) {
          if (j.size > j.offset) pending += j.size - j.offset;
        }
        if (f.size + pending > u.left) {
          _toast(Lc.current.cloudNoRoom(bytesText(u.left)));
          return;
        }
      }
    } catch (_) {
      // 额度问不到就先放行，交给服务端兜着
    }
    UploadManager.i.add(f);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(Lc.current.transfers)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _tab == 0 ? _pickToDownload : _uploadEntry,
        icon: Icon(_tab == 0 ? Icons.download_rounded : Icons.upload_file),
        label: Text(_tab == 0 ? Lc.current.download : Lc.current.upload),
      ),
      body: PageWidth(
        child: SegmentedPages(
          onChanged: (i) => setState(() => _tab = i),
          labels: [Lc.current.download, Lc.current.uploadsTab],
          children: const [DownloadsTab(), UploadsView()],
        ),
      ),
    );
  }
}

/// 下载：正在下的摊在上面，已下载的接在下面。
///
/// 没在下的就不占地方，直接露出已下载那一摞。
class DownloadsTab extends StatelessWidget {
  const DownloadsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AnimatedBuilder(
          animation: DownloadManager.i,
          builder: (context, _) {
            final jobs = DownloadManager.i.jobs;
            if (jobs.isEmpty) return const SizedBox.shrink();
            return PageWidth(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SectionTitle(Lc.current.downloading),
                    for (final j in jobs) _DownloadRow(job: j),
                  ],
                ),
              ),
            );
          },
        ),
        const Expanded(child: DownloadsPage(embedded: true)),
      ],
    );
  }
}

/// 正在下的那一条：文件名、进度、掐掉的按钮。
class _DownloadRow extends StatelessWidget {
  const _DownloadRow({required this.job});

  final DownloadJob job;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pct = (job.progress * 100).clamp(0, 100).toStringAsFixed(0);
    final got = job.received;
    final sub = got == null
        ? '$pct%'
        : '${bytesText(got)}'
              '${job.total > 0 ? ' / ${bytesText(job.total)}' : ''} · $pct%';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
      child: Row(
        children: [
          Icon(fileIconFor(job.name), size: 24, color: cs.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  job.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: job.progress > 0 ? job.progress : null,
                    minHeight: 3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(sub, style: TextStyle(fontSize: 11.5, color: cs.outline)),
              ],
            ),
          ),
          IconButton(
            tooltip: Lc.current.cancel,
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => DownloadManager.i.cancel(job.key),
          ),
        ],
      ),
    );
  }
}

/// 上传队列。队列归 UploadManager 管，这页只是把它摊开来看。
class UploadsView extends StatelessWidget {
  const UploadsView({super.key});

  @override
  Widget build(BuildContext context) {
    return PageWidth(
      child: AnimatedBuilder(
        animation: UploadManager.i,
        builder: (context, _) {
          final m = UploadManager.i;
          final active = m.activeJobs;
          final waiting = m.failedJobs;
          final done = [
            for (final j in m.jobs)
              if (j.state == UploadState.done) j,
          ];
          if (active.isEmpty && waiting.isEmpty && done.isEmpty) {
            return EmptyView(
              icon: Icons.cloud_upload_outlined,
              title: Lc.current.uploadsEmpty,
              hint: Lc.current.uploadsEmptyHint,
            ).scrollable();
          }
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              if (active.isNotEmpty) ...[
                _SectionTitle(Lc.current.uploadsRunningN('${active.length}')),
                for (final j in active)
                  _JobTile(job: j, onCancel: () => m.cancel(j)),
              ],
              if (waiting.isNotEmpty) ...[
                _SectionTitle(Lc.current.uploadsFailedN('${waiting.length}')),
                for (final j in waiting)
                  _JobTile(
                    job: j,
                    onCancel: () => m.discard(j),
                    onRetry: () => m.retry(j),
                  ),
              ],
              if (done.isNotEmpty) ...[
                _SectionTitle(
                  Lc.current.uploadsDoneN('${done.length}'),
                  action: TextButton(
                    onPressed: m.clearFinished,
                    child: Text(Lc.current.clearFinished),
                  ),
                ),
                for (final j in done.reversed.take(20)) _JobTile(job: j),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

class _JobTile extends StatelessWidget {
  const _JobTile({required this.job, this.onCancel, this.onRetry});

  final UploadJob job;
  final VoidCallback? onCancel;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final running = job.state == UploadState.running;
    final failed =
        job.state == UploadState.failed || job.state == UploadState.cancelled;
    final done = job.state == UploadState.done;
    final queued = job.state == UploadState.queued;
    final total = job.size;
    final got = running ? job.got : (done ? total : job.offset);
    final pct = total > 0 ? (got / total).clamp(0.0, 1.0) : null;
    final rate = running && job.speed > 0
        ? '${bytesShort(job.speed.round())}/s'
        : '';
    final sub = <String>[
      if (queued) Lc.current.uploading,
      if (running)
        '${bytesShort(got)} / ${bytesShort(total)}'
            '${pct == null ? '' : ' · ${(pct * 100).toStringAsFixed(0)}%'}'
            '${rate.isEmpty ? '' : ' · $rate'}',
      if (failed) job.error.isNotEmpty ? job.error : Lc.current.uploadFailed,
      if (done) Lc.current.uploadedOk,
    ];
    return ListTile(
      leading: Icon(
        done
            ? Icons.check_circle_outline
            : failed
            ? Icons.error_outline
            : Icons.upload_file,
        color: done
            ? cs.primary
            : failed
            ? cs.error
            : cs.onSurfaceVariant,
      ),
      title: Text(job.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (sub.isNotEmpty)
            Text(
              sub.join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                color: failed ? cs.error : cs.outline,
              ),
            ),
          if (running || queued) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 4,
                backgroundColor: cs.surfaceContainerHighest,
              ),
            ),
          ],
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onRetry != null)
            IconButton(
              tooltip: Lc.current.retry,
              icon: const Icon(Icons.refresh),
              onPressed: onRetry,
            ),
          if (onCancel != null)
            IconButton(
              tooltip: Lc.current.cancel,
              icon: const Icon(Icons.close),
              onPressed: onCancel,
            ),
        ],
      ),
    );
  }
}
