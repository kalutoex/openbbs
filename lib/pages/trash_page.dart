import 'package:flutter/material.dart';

import '../cloud.dart';
import '../l10n/error_text.dart';
import '../l10n/l10n.dart';
import '../trash.dart';
import '../widgets/empty_view.dart';
import '../widgets/file_card.dart';
import '../widgets/page_width.dart';
import '../widgets/segmented_pages.dart';
import '../widgets/toast.dart';

/// 回收站：自己删掉的帖子、自己删掉的云盘文件，都在这儿，还能捞回来。
///
/// 管理员删掉别人的东西不在这儿，在「管理员回收站」——那是另一条线，
/// 原主人根本看不见它。
class TrashPage extends StatefulWidget {
  const TrashPage({super.key});

  @override
  State<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends State<TrashPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(Lc.current.recycleBin)),
      body: PageWidth(
        child: SegmentedPages(
          labels: [Lc.current.trashThreadsTab, Lc.current.trashFilesTab],
          children: const [ThreadTrashView(), CloudTrashView()],
        ),
      ),
    );
  }
}

/// 还剩多久被清掉。跟云盘回收站同一套说法。
String trashLeftText(int? sec) {
  if (sec == null) return '';
  final d = Duration(seconds: sec);
  if (d.inDays >= 1) return Lc.current.daysLeft('${d.inDays}');
  if (d.inHours >= 1) return Lc.current.hoursLeft('${d.inHours}');
  return Lc.current.expiringSoon;
}

// ---------------------------------------------------------------- 云盘文件

class CloudTrashView extends StatefulWidget {
  const CloudTrashView({super.key, this.showOwner = false});

  /// 管理员回收站里要看是谁的文件。
  final bool showOwner;

  @override
  State<CloudTrashView> createState() => _CloudTrashViewState();
}

class _CloudTrashViewState extends State<CloudTrashView> {
  List<CloudFile>? _items;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final v = await CloudApi.trash();
      if (!mounted) return;
      setState(() {
        _items = v;
        _failed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  Future<void> _restore(CloudFile f) async {
    try {
      await CloudApi.restore(f.id);
      if (!mounted) return;
      setState(() => _items?.removeWhere((x) => x.id == f.id));
      toast(context, Lc.current.restored);
    } catch (e) {
      if (mounted) toast(context, errorText(context, e));
    }
  }

  Future<void> _purge(CloudFile f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Lc.current.deleteForever),
        content: Text(Lc.current.deleteForeverHint),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(Lc.current.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(Lc.current.delete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await CloudApi.purge(f.id);
      if (!mounted) return;
      setState(() => _items?.removeWhere((x) => x.id == f.id));
      toast(context, Lc.current.deletedForever);
    } catch (e) {
      if (mounted) toast(context, errorText(context, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = _items;
    return PageWidth(
      child: RefreshIndicator(
        onRefresh: _load,
        child: items == null
            ? Center(
                child: _failed
                    ? TextButton(
                        onPressed: _load,
                        child: Text(Lc.current.notConnectedTapRetry),
                      )
                    : const CircularProgressIndicator(),
              )
            : items.isEmpty
            ? EmptyView(
                icon: Icons.delete_outline,
                title: Lc.current.trashEmptyFiles,
                hint: Lc.current.trashKeptHint,
              ).scrollable()
            : ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final f = items[i];
                  return ListTile(
                    leading: Icon(fileIconFor(f.name), color: cs.outline),
                    title: Text(
                      f.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${bytesText(f.size)} · ${trashLeftText(f.expiresIn)}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: () => _restore(f),
                          child: Text(Lc.current.restore),
                        ),
                        IconButton(
                          tooltip: Lc.current.deleteForever,
                          icon: Icon(Icons.delete_forever, color: cs.error),
                          onPressed: () => _purge(f),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------- 帖子

class ThreadTrashView extends StatefulWidget {
  const ThreadTrashView({super.key});

  @override
  State<ThreadTrashView> createState() => _ThreadTrashViewState();
}

class _ThreadTrashViewState extends State<ThreadTrashView> {
  List<TrashThread>? _items;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final v = await TrashApi.threads();
      if (!mounted) return;
      setState(() {
        _items = v;
        _failed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  Future<void> _restore(TrashThread t) async {
    try {
      await TrashApi.restoreThread(t.id);
      if (!mounted) return;
      setState(() => _items?.removeWhere((x) => x.id == t.id));
      toast(context, Lc.current.threadBack);
    } catch (e) {
      if (mounted) toast(context, errorText(context, e));
    }
  }

  Future<void> _purge(TrashThread t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Lc.current.deleteForever),
        content: Text(Lc.current.threadPurgeHint),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(Lc.current.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(Lc.current.delete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await TrashApi.purgeThread(t.id);
      if (!mounted) return;
      setState(() => _items?.removeWhere((x) => x.id == t.id));
      toast(context, Lc.current.deletedForever);
    } catch (e) {
      if (mounted) toast(context, errorText(context, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = _items;
    return PageWidth(
      child: RefreshIndicator(
        onRefresh: _load,
        child: items == null
            ? Center(
                child: _failed
                    ? TextButton(
                        onPressed: _load,
                        child: Text(Lc.current.notConnectedTapRetry),
                      )
                    : const CircularProgressIndicator(),
              )
            : items.isEmpty
            ? EmptyView(
                icon: Icons.delete_outline,
                title: Lc.current.trashEmptyThreads,
                hint: Lc.current.trashThreadHint,
              ).scrollable()
            : ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final t = items[i];
                  final sub = <String>[
                    Lc.current.repliesCount('${t.replyCount}'),
                    if (t.excerpt.isNotEmpty) t.excerpt,
                    trashLeftText(t.expiresIn),
                  ];
                  return ListTile(
                    leading: Icon(Icons.article_outlined, color: cs.outline),
                    title: Text(
                      t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      sub.join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: () => _restore(t),
                          child: Text(Lc.current.restore),
                        ),
                        IconButton(
                          tooltip: Lc.current.deleteForever,
                          icon: Icon(Icons.delete_forever, color: cs.error),
                          onPressed: () => _purge(t),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}
