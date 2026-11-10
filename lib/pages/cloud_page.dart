import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../download_manager.dart';
import '../cloud.dart';
import '../paged.dart';
import '../download_index.dart';
import '../local_files.dart';
import '../pages/transfers_page.dart';
import '../file_browser.dart';
import '../l10n/error_text.dart';
import '../upload_manager.dart';
import '../utils.dart';
import '../widgets/empty_view.dart';
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
  final TextEditingController _search = TextEditingController();
  final ScrollController _scroll = ScrollController();

  String _q = '';
  String _sort = 'time';

  static const _perPage = 20;

  late final Pager<CloudFile> _pager = Pager(
    size: _perPage,
    fetch: (page) async {
      final p = await CloudApi.list(
        q: _q,
        sort: _sort,
        page: page,
        perPage: _perPage,
      );
      return PageSlice(p.items, hasMore: page * _perPage < p.total);
    },
  );

  List<CloudFile> get _items => _pager.items;
  bool get _loading => _pager.busy && _pager.isEmpty;
  bool get _more => _pager.loadingMore;
  bool get _failed => _pager.error != null;

  /// 上传统一在 UploadManager 里跑，退出这页也不会停。
  int _seenDone = 0;

  /// 搜索防抖。每敲一个字都打一次接口，翻页状态还会互相打架。
  Timer? _debounce;

  /// 云盘 id -> 本机那份。下载过就记着，开了 app 也能认出来。
  final Map<int, LocalDownload> _local = {};

  /// 文件名 -> 本机那份。从帖子附件下的没带云盘 id，按名字兜一下。
  final Map<String, LocalDownload> _localByName = {};

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    UploadManager.i.addListener(_onUpload);
    _seenDone = UploadManager.i.doneCount;
    _loadLocal();
    _load();
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
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    if (p.pixels >= p.maxScrollExtent - 300) _load(reset: false);
  }

  Future<void> _load({bool reset = true}) async {
    setState(() {});
    if (reset) {
      await _pager.reset();
    } else {
      await _pager.more();
    }
    // 额度跟着列表一起刷，失败不挡列表。
    try {
      final u = await CloudApi.usage();
      if (mounted) setState(() => _usage = u);
    } catch (_) {}
    if (!mounted) return;
    setState(() {});
    final e = _pager.error;
    if (e != null && reset) {
      _pager.clearError();
      toastOf(context, e);
    }
  }

  /// 这页只管看和管理。真要落到手机上，交给「传输」，那儿能看见进度。
  ///
  /// 本机已经有一份的，直接带他去文件所在的那层目录，不再下一遍。
  Future<void> _open(CloudFile f) async {
    final local = _localOf(f);
    if (local != null && await _reveal(f, local)) return;
    final key = DownloadManager.keyForCloud(f.id);
    if (DownloadManager.i.isDownloading(key)) {
      await _toTransfers();
      return;
    }
    final url = f.url.startsWith('http') ? f.url : '${Api.base}${f.url}';
    try {
      // 不等它传完：大文件要下好一会儿，人得能去看别的东西。
      unawaited(
        DownloadManager.i.start(
          key,
          url,
          f.name,
          total: f.size,
          cloudId: '${f.id}',
        ),
      );
      await _toTransfers();
    } catch (e) {
      if (!mounted) return;
      if (mounted) {
        toastOf(context, errorText(context, e));
      }
    }
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
          refs > 0
              ? '${Lc.current.cloudRefsWarn('$refs')}\n\n$trashHint'
              : trashHint,
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
      if (mounted) {
        toastOf(context, errorText(context, e));
      }
    }
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
      body: PageWidth(
        child: RefreshIndicator(
          onRefresh: () => _load(),
          child: Column(
            children: [
              if (_usage != null) _UsageBar(usage: _usage!),
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
    final ended = !_pager.hasMore;
    final tail = _more || (_items.length > _perPage && ended) ? 1 : 0;
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
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
        return _FileRow(
          file: f,
          onTap: () => _open(f),
          // 长按只删这一条。整页不再有多选。
          onLongPress: () => _deleteOne(f),
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
                autocorrect: false,
                enableSuggestions: false,
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
  });

  final CloudFile file;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final refs = file.refs;
    final sub = StringBuffer(bytesText(file.size));
    if (file.createdAt > 0) sub.write(' · ${timeAgo(file.createdAt)}');
    // 一行一张卡：圆角、描边。行高和原来一样，只是多了边界。
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              Icon(fileIconFor(file.name), size: 26, color: cs.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14.5),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      sub.toString(),
                      style: TextStyle(fontSize: 12, color: cs.outline),
                    ),
                    if (refs > 0)
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
      ),
    );
  }
}
