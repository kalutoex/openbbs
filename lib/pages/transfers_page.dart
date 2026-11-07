import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../upload_manager.dart';
import '../utils.dart';
import '../widgets/empty_view.dart';
import '../widgets/page_width.dart';
import 'downloads_page.dart';

/// 传输：上传的和已经下到本机的，一个地方看。
///
/// 以前这两样各挂一个按钮在云盘右上角，谁都不在那两页上待着。
class TransfersPage extends StatefulWidget {
  const TransfersPage({super.key});

  @override
  State<TransfersPage> createState() => _TransfersPageState();
}

class _TransfersPageState extends State<TransfersPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(Lc.current.transfers),
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: Lc.current.uploadsTab),
            Tab(text: Lc.current.downloadsTab),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [UploadsView(), DownloadsPage(embedded: true)],
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
                  _JobTile(
                    job: j,
                    onCancel: () => m.cancel(j),
                  ),
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
