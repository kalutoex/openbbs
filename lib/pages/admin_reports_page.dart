import 'package:flutter/material.dart';

import '../api.dart';
import '../widgets/page_width.dart';
import '../store.dart';
import '../utils.dart';
import 'thread_page.dart';

import '../l10n/error_text.dart';
import '../l10n/l10n.dart';
import '../widgets/empty_view.dart';
import '../widgets/toast.dart';

/// 管理员看举报。删掉或者认定没问题，二选一。
class AdminReportsPage extends StatefulWidget {
  const AdminReportsPage({super.key});

  @override
  State<AdminReportsPage> createState() => _AdminReportsPageState();
}

class _AdminReportsPageState extends State<AdminReportsPage> {
  final List<Map<String, dynamic>> _items = [];
  int _page = 1;
  int _total = 0;
  bool _first = true;
  bool _busy = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      if (reset) {
        _page = 1;
        _err = null;
      }
    });
    try {
      final r = await Api.get('/admin/reports', query: {'page': '$_page'});
      final items = ((r['items'] as List?) ?? const [])
          .cast<Map<String, dynamic>>();
      setState(() {
        if (reset) _items.clear();
        _items.addAll(items);
        _total = (r['total'] ?? 0) as int;
        _first = false;
        AppState.instance.setReportOpen(_total);
      });
    } on ApiException catch (e) {
      setState(() {
        _err = errorText(context, e);
        _first = false;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handle(Map<String, dynamic> it, {required bool keep}) async {
    final id = it['id'] as int;
    String note;
    bool? ok = true;
    if (keep) {
      note = Lc.current.reportKeepNote;
    } else if (it['reply_id'] != null) {
      note = Lc.current.reportDeleteFloorNote;
    } else {
      note = Lc.current.reportDeletePostNote;
    }
    ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          keep
              ? Lc.current.ignoreReportConfirm
              : Lc.current.deleteContentConfirm,
        ),
        content: Text(note),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(Lc.current.cancel),
          ),
          FilledButton(
            style: keep
                ? null
                : FilledButton.styleFrom(
                    backgroundColor: Theme.of(ctx).colorScheme.error,
                    foregroundColor: Theme.of(ctx).colorScheme.onError,
                  ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(keep ? Lc.current.ignore : Lc.current.deleteIt),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.post('/admin/reports/$id?keep=$keep', const {});
      if (!mounted) return;
      setState(() {
        _items.removeWhere((e) => e['id'] == id);
        _total = _total > 0 ? _total - 1 : 0;
      });
      AppState.instance.setReportOpen(_total);
      toast(context, keep ? Lc.current.ignored : Lc.current.deleted);
    } on ApiException catch (e) {
      if (!mounted) return;
      toast(context, errorText(context, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _total > 0 ? Lc.current.reportsCount('${_total}') : Lc.current.report,
        ),
        actions: [
          IconButton(
            onPressed: () => _load(reset: true),
            icon: const Icon(Icons.refresh),
            tooltip: Lc.current.refresh,
          ),
        ],
      ),
      body: PageWidth(
        child: _first
            ? const Center(child: CircularProgressIndicator())
            : _buildBody(cs),
      ),
    );
  }

  Widget _buildBody(ColorScheme cs) {
    if (_err != null) {
      return EmptyView(
        icon: Icons.cloud_off_rounded,
        title: _err!,
        error: true,
        action: FilledButton.tonal(
          onPressed: () => _load(reset: true),
          child: Text(Lc.current.retry),
        ),
      );
    }
    if (_items.isEmpty) {
      return EmptyView(icon: Icons.flag_outlined, title: Lc.current.noReports);
    }
    return ListView.separated(
      itemCount: _items.length + 1,
      separatorBuilder: (_, i) => i < _items.length - 1
          ? const Divider(height: 1, indent: 16, endIndent: 16)
          : const SizedBox.shrink(),
      itemBuilder: (ctx, i) {
        if (i == _items.length) {
          if (_items.length >= _total) return const SizedBox(height: 24);
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Center(
              child: TextButton(
                onPressed: () {
                  _page++;
                  _load();
                },
                child: Text(Lc.current.loadMore),
              ),
            ),
          );
        }
        final it = _items[i];
        final kind = it['reply_id'] != null
            ? Lc.current.floor
            : Lc.current.post;
        return InkWell(
          onTap: () {
            final tid = it['thread_id'];
            if (tid == null) return;
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ThreadPage(
                  threadId: tid as int,
                  title: (it['thread_title'] ?? '') as String,
                ),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        kind,
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        (it['thread_title'] ?? '') as String,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      timeAgo((it['created_at'] ?? 0) as int),
                      style: TextStyle(fontSize: 11, color: cs.outline),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  (it['text'] ?? '') as String,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 4),
                Text(
                  Lc.current.reportLine(
                    '${(it['reason'] ?? '')}',
                    '${(it['reporter'] ?? '')}',
                  ),
                  style: TextStyle(fontSize: 11, color: cs.outline),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => _handle(it, keep: true),
                      child: Text(Lc.current.ignore),
                    ),
                    const SizedBox(width: 4),
                    TextButton(
                      style: TextButton.styleFrom(foregroundColor: cs.error),
                      onPressed: () => _handle(it, keep: false),
                      child: Text(Lc.current.deleteIt),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
