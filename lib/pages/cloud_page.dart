import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../download_manager.dart';
import '../cloud.dart';
import '../download_index.dart';
import '../downloads.dart';
import '../local_files.dart';
import '../pages/transfers_page.dart';
import '../file_browser.dart';
import '../file_pick.dart';
import '../l10n/error_text.dart';
import '../upload_manager.dart';
import '../utils.dart';
import '../widgets/empty_view.dart';
import '../widgets/app_sheet.dart';
import '../widgets/page_width.dart';
import '../widgets/file_card.dart';

import '../l10n/l10n.dart';
import '../widgets/toast.dart';

/// 云盘：我自己传上来的东西。
///
/// 只放自己上传的；帖子里的附件发帖时也算进来，删了帖子文件还在。
class CloudPage extends StatefulWidget {
  const CloudPage({super.key});

  @override
  State<CloudPage> createState() => _CloudPageState();
}

class _CloudPageState extends State<CloudPage> {
  CloudUsage? _usage;
  final List<CloudFile> _items = [];
  final TextEditingController _search = TextEditingController();
  final ScrollController _scroll = ScrollController();

  bool _loading = true;
  bool _more = false;
  bool _failed = false;
  String _q = '';
  String _sort = 'time';
  int _page = 1;
  int _total = 0;

  static const _perPage = 20;

  /// 上传统一在 UploadManager 里跑，退出这页也不会停。
  int _seenDone = 0;

  /// 搜索防抖。每敲一个字都打一次接口，翻页状态还会互相打架。
  Timer? _debounce;

  /// 这次进来已经下完的，行尾给个绿标。还能再下，标不会清。
  final Set<int> _done = {};

  /// 云盘 id -> 本机那份。下载过就记着，开了 app 也能认出来。
  final Map<int, LocalDownload> _local = {};

  /// 文件名 -> 本机那份。从帖子附件下的没带云盘 id，按名字兜一下。
  final Map<String, LocalDownload> _localByName = {};

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    UploadManager.i.addListener(_onUpload);
    DownloadManager.i.addListener(_onDownload);
    _seenDone = UploadManager.i.doneCount;
    _loadLocal();
    _load();
  }

  /// 下载也不归这页管，进度直接从队列里读，变了就重画那一行。
  void _onDownload() {
    if (mounted) setState(() {});
  }

  /// 上传不归这页管，所以它传完了得回头叫一声：列表和额度都变了。
  void _onUpload() {
    if (!mounted) return;
    if (UploadManager.i.doneCount != _seenDone) {
      _seenDone = UploadManager.i.doneCount;
      _load();
    }
  }



  /// 本机下载记录：认出哪些已经在自己手机上，点的时候不重复下。
  Future<void> _loadLocal() async {
    final recs = await loadLocalDownloads();
    final map = <int, LocalDownload>{};
    final byName = <String, LocalDownload>{};
    for (final r in recs) {
      final id = int.tryParse(r.cloudId ?? '');
      if (id != null) map.putIfAbsent(id, () => r);
      byName.putIfAbsent(r.name, () => r);
    }
    if (!mounted) return;
    setState(() {
      _local
        ..clear()
        ..addAll(map);
      _localByName
        ..clear()
        ..addAll(byName);
    });
  }

  /// 这个云盘文件在本机的哪一份。先认 id，再认名字。
  LocalDownload? _localOf(CloudFile f) => _local[f.id] ?? _localByName[f.name];

  @override
  void dispose() {
    _debounce?.cancel();
    UploadManager.i.removeListener(_onUpload);
    DownloadManager.i.removeListener(_onDownload);
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    if (p.pixels >= p.maxScrollExtent - 300) _loadMore();
  }

  Future<void> _load({bool reset = true}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _failed = false;
        _page = 1;
      });
    }
    try {
      final u = await CloudApi.usage();
      final p = await CloudApi.list(
        q: _q,
        sort: _sort,
        page: 1,
        perPage: _perPage,
      );
      if (!mounted) return;
      setState(() {
        _usage = u;
        _items
          ..clear()
          ..addAll(p.items);
        _total = p.total;
        _page = 1;
        _loading = false;
        _failed = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
      if (!reset) return;
      _toast(errorText(context, e));
    }
  }

  Future<void> _loadMore() async {
    if (_more || _loading) return;
    if (_items.length >= _total) return;
    setState(() => _more = true);
    try {
      final p = await CloudApi.list(
        q: _q,
        sort: _sort,
        page: _page + 1,
        perPage: _perPage,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(p.items);
        _page += 1;
        _total = p.total;
        _more = false;
      });
    } catch (_) {
      if (mounted) setState(() => _more = false);
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    toast(context, text);
  }

  Future<void> _open(CloudFile f) async {
    final key = DownloadManager.keyForCloud(f.id);
    if (DownloadManager.i.isDownloading(key)) return; // 同一个文件别叠着下
    // 本机已经有了：不重下，带他去文件所在的那层目录，里面再点才打开。
    final local = _localOf(f);
    if (local != null && await _reveal(f, local)) return;
    final url = f.url.startsWith('http') ? f.url : '${Api.base}${f.url}';
    try {
      final saved = await DownloadManager.i.start(
        key,
        url,
        f.name,
        total: f.size,
        cloudId: '${f.id}',
      );
      if (!mounted || saved == null) return;
      setState(() => _done.add(f.id));
      // 刚下完，本地记录也更新一下，再点就是带你去找文件
      await _loadLocal();
      // 落点只说一次；之后看行里的绿标就够了，不再弹提示。
      if (await DownloadHint.firstTime()) {
        if (mounted) _toast(Lc.current.savedTo(saved.display));
      }
    } catch (e) {
      if (!mounted) return;
      _toast(errorText(context, e));
    }
  }

  /// 下到一半不下了。连接掐掉，半截文件也跟着删。
  void _cancelDownload(CloudFile f) {
    DownloadManager.i.cancel(DownloadManager.keyForCloud(f.id));
  }

  /// 去本机那份文件所在的位置。文件被删了就返回 false，转去正常下载。
  Future<bool> _reveal(CloudFile f, LocalDownload local) async {
    final path = await localFileOf(local);
    if (path == null) {
      // 记录还在、文件没了：把这条清掉，下次点就是重新下
      await forgetLocalDownload(local.display);
      if (mounted) setState(() => _local.remove(f.id));
      return false;
    }
    final cut = path.lastIndexOf('/');
    if (cut <= 0) return false;
    if (!mounted) return false;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FileBrowserPage(
          openOnly: true,
          initialPath: path.substring(0, cut),
          highlight: path.substring(cut + 1),
        ),
      ),
    );
    return true;
  }

  /// 删一个。长按那条进来的，删完给一次撤销。
  Future<void> _deleteOne(CloudFile f) async {
    final ids = [f.id];
    final refs = f.refs;
    final trashHint = Lc.current.goesToTrashHint;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Lc.current.deleteThisFile),
        content: Text(
          refs > 0 ? '${Lc.current.cloudRefsWarn('$refs')}\n\n$trashHint' : trashHint,
        ),
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
    await _removeIds(ids, refs: refs);
  }

  Future<void> _removeIds(List<int> ids, {int refs = 0}) async {
    if (ids.isEmpty) return;
    try {
      for (final id in ids) {
        await CloudApi.remove(id);
      }
      if (!mounted) return;
      setState(() {
        _items.removeWhere((x) => ids.contains(x.id));
      });
      _load(reset: false);
      if (!mounted) return;
      toast(
        context,
        ids.length == 1
            ? Lc.current.movedToTrash
            : Lc.current.movedToTrashN('${ids.length}'),
        action: SnackBarAction(
          label: Lc.current.undo,
          onPressed: () async {
            // 回收站里的东西还能拉回来，错点一下不至于心疼
            for (final id in ids) {
              try {
                await CloudApi.restore(id);
              } catch (_) {}
            }
            if (mounted) _load();
          },
        ),
      );
    } catch (e) {
      if (mounted) _toast(errorText(context, e));
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
      final up = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => const FileBrowserPage()),
      );
      if (up == true && mounted) _load();
    } else {
      await _upload();
    }
  }

  /// 选一个文件就交给上传队列。这里不等着它传完——
  /// 1GB 要十几分钟，人不能卡在这一页上。传完管理器会自己回来喊一声。
  Future<void> _upload() async {
    final f = await pickFile();
    if (f == null) return;
    _enqueue(f);
  }

  /// 进队列前先自己看一眼额度。
  ///
  /// 服务端也会拦，但那是传了几分钟之后才知道；能在选完文件的一秒钟里
  /// 说清楚的事，不该让人等那么久。
  void _enqueue(PickedFile f) {
    final u = _usage;
    if (u != null && !u.unlimited) {
      // 已经排在队里的也要算进去，不然一次选十个就都放行了
      var pending = 0;
      for (final j in UploadManager.i.activeJobs) {
        if (j.size > j.offset) pending += j.size - j.offset;
      }
      if (f.size + pending > u.left) {
        _toast(Lc.current.cloudNoRoom(bytesText(u.left)));
        return;
      }
    }
    UploadManager.i.add(f);
  }

  Future<void> _toTransfers() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TransfersPage()),
    );
    // 那边可能删了文件、也可能传完了，回来重新认一遍
    if (mounted) _loadLocal();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(Lc.current.cloudDisk),
        actions: [
          // 右上角只留一个：上传队列和已下载都在「传输」里。
          IconButton(
            tooltip: Lc.current.transfers,
            icon: const Icon(Icons.swap_vert_rounded),
            onPressed: _toTransfers,
          ),
        ],
      ),
      floatingActionButton: AnimatedBuilder(
        animation: UploadManager.i,
        builder: (context, _) {
          // 忙也照选：选好自动排队，不用等一个 1GB 的包传完才让点。
          final waiting = UploadManager.i.activeJobs.length;
          return FloatingActionButton.extended(
            onPressed: _uploadEntry,
            icon: waiting > 0
                ? Badge(
                    label: Text('$waiting'),
                    child: const Icon(Icons.upload_file),
                  )
                : const Icon(Icons.upload_file),
            label: Text(
              waiting > 0 ? Lc.current.uploadQueuedN('$waiting') : Lc.current.upload,
            ),
          );
        },
      ),
      body: PageWidth(
        child: RefreshIndicator(
          onRefresh: () => _load(),
          child: Column(
            children: [
              if (_usage != null) _UsageBar(usage: _usage!),
              _UploadStrip(onTap: _toTransfers),
              _SearchBar(
                controller: _search,
                onChanged: (v) {
                  // 敲一个字就打一次接口，翻页状态还会互相打架
                  _debounce?.cancel();
                  setState(() => _q = v);
                  _debounce = Timer(const Duration(milliseconds: 320), _load);
                },
                sort: _sort,
                onSort: (s) {
                  setState(() => _sort = s);
                  _load();
                },
              ),
              Expanded(child: _body()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_failed) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          Center(
            child: TextButton(
              onPressed: () => _load(),
              child: Text(Lc.current.notConnectedTapRetry),
            ),
          ),
        ],
      );
    }
    if (_items.isEmpty) {
      return EmptyView(
        icon: _q.isEmpty ? Icons.cloud_outlined : Icons.search_off_rounded,
        title: _q.isEmpty ? Lc.current.nothingUploadedYet : Lc.current.notFound,
      );
    }
    final ended = _items.length >= _total;
    final tail = _more || (_items.length > _perPage && ended) ? 1 : 0;
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: _items.length + tail,
      itemBuilder: (context, i) {
        if (i >= _items.length) {
          if (_more) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          // 翻到底了说一声，省得人一直往上划，以为还有
          return Padding(
            padding: const EdgeInsets.fromLTRB(0, 18, 0, 8),
            child: Center(
              child: Text(
                Lc.current.noMore,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ),
          );
        }
        final f = _items[i];
        final dlKey = DownloadManager.keyForCloud(f.id);
        final dlProgress = DownloadManager.i.progressOf(dlKey);
        return _FileRow(
          file: f,
          onTap: () => _open(f),
          // 长按只删这一条。整页不再有多选。
          onLongPress: () => _deleteOne(f),
          onCancelDownload: (dlProgress ?? 0) > 0 ? () => _cancelDownload(f) : null,
          progress: dlProgress,
          downloaded: _done.contains(f.id) || _localOf(f) != null,
        );
      },
    );
  }
}

class _UsageBar extends StatelessWidget {
  const _UsageBar({required this.usage});

  final CloudUsage usage;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final usedText = bytesText(usage.used);
    final quotaText = usage.unlimited ? '' : bytesText(usage.quota!);
    final countText = Lc.current.fileCount2('${usage.count}');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                usage.unlimited
                    ? Lc.current.usedSpace(usedText)
                    : Lc.current.usedOfTotal(usedText, quotaText),
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
              ),
              const Spacer(),
              Text(
                countText,
                style: TextStyle(fontSize: 12, color: cs.outline),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: usage.unlimited ? 0 : usage.ratio,
              minHeight: 5,
              backgroundColor: cs.surfaceContainerHighest,
              color: usage.ratio > 0.9 ? cs.error : cs.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.onChanged,
    required this.sort,
    required this.onSort,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String sort;
  final ValueChanged<String> onSort;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 38,
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                textAlignVertical: TextAlignVertical.center,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: Lc.current.findFile,
                  prefixIcon: const Icon(Icons.search, size: 18),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  filled: true,
                  fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(19),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: Text(sort == 'size' ? Lc.current.bySize : Lc.current.byTime),
            selected: false,
            onSelected: (_) => onSort(sort == 'size' ? 'time' : 'size'),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.file,
    required this.onTap,
    required this.onLongPress,
    this.progress,
    this.downloaded = false,
    this.onCancelDownload,
  });

  final CloudFile file;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  /// 正在下载就是 0..1，没在下就是 null。
  final double? progress;

  /// 这次进来下过了。还能再点，标一直留着。
  final bool downloaded;

  /// 正下着的时候给个 ×，点它能停。
  final VoidCallback? onCancelDownload;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final refs = file.refs;
    final p = progress;
    final sub = StringBuffer(bytesText(file.size));
    if (file.createdAt > 0) sub.write(' · ${timeAgo(file.createdAt)}');
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            Icon(
              fileIconFor(file.name),
              size: 26,
              color: p == null ? cs.primary : cs.outline,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          file.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14.5),
                        ),
                      ),
                      if (downloaded) ...[
                        const SizedBox(width: 6),
                        const _DoneBadge(),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  if (p == null)
                    Text(
                      sub.toString(),
                      style: TextStyle(fontSize: 12, color: cs.outline),
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: p > 0 ? p.clamp(0.0, 1.0) : null,
                              minHeight: 3,
                              backgroundColor: cs.surfaceContainerHighest,
                              color: cs.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          p > 0
                              ? '${(p * 100).clamp(0, 100).toStringAsFixed(0)}%'
                              : Lc.current.downloadingShort,
                          style: TextStyle(fontSize: 11, color: cs.primary),
                        ),
                        if (onCancelDownload != null)
                          InkWell(
                            onTap: onCancelDownload,
                            borderRadius: BorderRadius.circular(14),
                            child: Padding(
                              padding: const EdgeInsets.all(2),
                              child: Icon(
                                Icons.close,
                                size: 16,
                                color: cs.outline,
                              ),
                            ),
                          ),
                      ],
                    ),
                  if (refs > 0 && p == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        Lc.current.usedByPosts('$refs'),
                        style: TextStyle(fontSize: 11.5, color: cs.primary),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 行尾那个绿标。下载过一次就给，之后一直在。
class _DoneBadge extends StatelessWidget {
  const _DoneBadge();

  static const _green = Color(0xFF2E7D32);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: _green.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        Lc.current.downloadedBadge,
        style: const TextStyle(fontSize: 10.5, color: _green),
      ),
    );
  }
}

/// 上传队列那一条。
///
/// 传 1GB 的时候，有没有这一条决定了「它到底在不在动」。
/// 现在队列能排好几个，所以一条一条列出来，正在传的带进度，
/// 排队的只报个名字。每条都能点 × 停掉，传砸了的点一下就重试。
class _UploadStrip extends StatelessWidget {
  const _UploadStrip({this.onTap});

  /// 点一下去「传输」，那儿能看完整的队列。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: UploadManager.i,
      builder: (context, _) {
        final active = UploadManager.i.activeJobs;
        final failed = UploadManager.i.failedJobs;
        if (active.isEmpty && failed.isEmpty) {
          return const SizedBox.shrink();
        }
        return InkWell(
          onTap: onTap,
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final j in active.take(3))
              _UploadPanel(
                job: j,
                onCancel: () => UploadManager.i.cancel(j),
                onRetry: null,
              ),
            if (active.length > 3)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 16, 6),
                child: Text(
                  Lc.current.moreQueuedN('${active.length - 3}'),
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ),
            // 失败的不自动消失：人得知道哪个没传上去
            for (final j in failed.take(2))
              _UploadPanel(
                job: j,
                onCancel: () => UploadManager.i.discard(j),
                onRetry: () => UploadManager.i.retry(j),
              ),
          ],
          ),
        );
      },
    );
  }
}

class _UploadPanel extends StatelessWidget {
  const _UploadPanel({
    required this.job,
    this.onCancel,
    this.onRetry,
  });

  final UploadJob job;
  final VoidCallback? onCancel;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = job.name;
    final total = job.size;
    final running = job.state == UploadState.running;
    final failed = job.retryable;
    final got = running ? job.got : (failed ? job.offset : 0);
    final speed = running ? job.speed : 0.0;
    final pct = total > 0 ? (got / total).clamp(0.0, 1.0) : null;
    final left =
        '${bytesShort(got)} / ${bytesShort(total > 0 ? total : got)}';
    final rate = speed > 0 ? '${bytesShort(speed.round())}/s' : '';
    final pctText = pct == null ? '' : '${(pct * 100).toStringAsFixed(0)}%';
    final title = failed && job.error.isNotEmpty ? '$name · ${job.error}' : name;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Row(
        children: [
          Icon(
            failed ? Icons.error_outline : Icons.upload_file,
            size: 18,
            color: failed ? cs.error : cs.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: failed ? cs.error : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (rate.isNotEmpty)
                      Text(
                        rate,
                        style: TextStyle(fontSize: 11.5, color: cs.outline),
                      ),
                  ],
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: failed ? (pct ?? 0) : pct,
                    minHeight: 5,
                    backgroundColor: cs.surfaceContainerHighest,
                    color: failed ? cs.error : cs.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      left,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    if (failed)
                      Text(
                        Lc.current.tapToRetry,
                        style: TextStyle(fontSize: 11.5, color: cs.error),
                      )
                    else
                      Text(
                        job.state == UploadState.queued
                            ? Lc.current.waitingTurn
                            : pctText,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: failed ? Lc.current.delete : Lc.current.cancel,
            icon: Icon(failed ? Icons.delete_outline : Icons.close, size: 18),
            onPressed: onCancel,
          ),
          if (failed)
            TextButton(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              onPressed: onRetry,
              child: Text(Lc.current.retry),
            ),
        ],
      ),
    );
  }
}
