import 'package:flutter/material.dart';

import '../api.dart';
import '../cloud.dart';
import '../downloads.dart';
import '../file_browser.dart';
import '../file_open.dart';
import '../file_pick.dart';
import '../l10n/error_text.dart';
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
  bool _uploading = false;

  /// 正在下的：id -> 0..1。列表里就着那一行显示进度。
  final Map<int, double> _dl = {};

  /// 这次进来已经下完的，行尾给个绿标。还能再下，标不会清。
  final Set<int> _done = {};

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
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
    if (_dl.containsKey(f.id)) return; // 同一个文件别叠着下
    final url = f.url.startsWith('http') ? f.url : '${Api.base}${f.url}';
    setState(() => _dl[f.id] = 0);
    try {
      final saved = await openRemoteFile(
        url,
        f.name,
        onProgress: (p) {
          if (mounted) setState(() => _dl[f.id] = p);
        },
      );
      if (!mounted) return;
      setState(() {
        _dl.remove(f.id);
        _done.add(f.id);
      });
      // 落点只说一次；之后看行里的绿标就够了，不再弹提示。
      if (await DownloadHint.firstTime()) {
        if (mounted) _toast(Lc.current.savedTo(saved.display));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _dl.remove(f.id));
      _toast(errorText(context, e));
    }
  }

  Future<void> _delete(CloudFile f) async {
    final used = f.refs;
    final trashHint = Lc.current.goesToTrashHint;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Lc.current.deleteThisFile),
        content: Text(
          used > 0
              ? '${Lc.current.cloudRefsWarn('$used')}\n\n$trashHint'
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
    try {
      await CloudApi.remove(f.id);
      if (!mounted) return;
      setState(() => _items.removeWhere((x) => x.id == f.id));
      _load(reset: false);
      _toast(Lc.current.movedToTrash);
    } catch (e) {
      if (mounted) _toast(errorText(context, e));
    }
  }

  void _menu(CloudFile f) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: Text(Lc.current.download),
              onTap: () {
                Navigator.pop(ctx);
                _open(f);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(Lc.current.delete),
              onTap: () {
                Navigator.pop(ctx);
                _delete(f);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 上传入口。手机上有内置的文件浏览器，可以翻整个存储；
  /// 别的地方（网页、桌面）还是系统选择器。
  Future<void> _uploadEntry() async {
    if (_uploading) return;
    if (!fileBrowserSupported) {
      await _upload();
      return;
    }
    final v = await showModalBottomSheet<String>(
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

  /// 选一个文件就传。传完刷新列表，额度条跟着变。
  Future<void> _upload() async {
    if (_uploading) return;
    final f = await pickFile();
    if (f == null) return;
    // 单文件不设死上限，能不能传看剩余空间——服务端会按额度掐断。
    setState(() => _uploading = true);
    _toast(Lc.current.uploadingFile2(f.name));
    try {
      await Api.uploadFile(f);
      if (!mounted) return;
      await _load();
      if (mounted) _toast(Lc.current.uploadedDone);
    } catch (e) {
      if (mounted) _toast(errorText(context, e));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _toTrash() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CloudTrashPage()),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(Lc.current.cloudDisk),
        actions: [
          IconButton(
            tooltip: Lc.current.recycleBin,
            icon: const Icon(Icons.delete_outline),
            onPressed: _toTrash,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _uploading ? null : _uploadEntry,
        icon: _uploading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.upload_file),
        label: Text(Lc.current.upload),
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
                  setState(() => _q = v);
                  _load();
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
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: _items.length + (_more ? 1 : 0),
      itemBuilder: (context, i) {
        if (i >= _items.length) {
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
        final f = _items[i];
        return _FileRow(
          file: f,
          onTap: () => _open(f),
          onLongPress: () => _menu(f),
          progress: _dl[f.id],
          downloaded: _done.contains(f.id),
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
                    ? Lc.current.usedSpace('${usedText}')
                    : Lc.current.usedOfTotal('${usedText}', '${quotaText}'),
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
  });

  final CloudFile file;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  /// 正在下载就是 0..1，没在下就是 null。
  final double? progress;

  /// 这次进来下过了。还能再点，标一直留着。
  final bool downloaded;

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
      child: Padding(
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

/// 回收站。7 天后服务端清掉，列表上给个倒计时。
class CloudTrashPage extends StatefulWidget {
  const CloudTrashPage({super.key});

  @override
  State<CloudTrashPage> createState() => _CloudTrashPageState();
}

class _CloudTrashPageState extends State<CloudTrashPage> {
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
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _restore(CloudFile f) async {
    try {
      await CloudApi.restore(f.id);
      if (!mounted) return;
      setState(() => _items?.removeWhere((x) => x.id == f.id));
      toast(context, Lc.current.restoredDone);
    } catch (e) {
      if (!mounted) return;
      toast(context, errorText(context, e));
    }
  }

  /// 彻底删除：不进 7 天倒计时，直接没了，空间当场还。
  Future<void> _purge(CloudFile f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Lc.current.deleteForever),
        content: Text('${f.name}\n\n${Lc.current.deleteForeverHint}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(Lc.current.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              Lc.current.deleteForever,
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
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
      if (!mounted) return;
      toast(context, errorText(context, e));
    }
  }

  String _left(int? sec) {
    if (sec == null) return '';
    final d = Duration(seconds: sec);
    final days = d.inDays;
    final hours = d.inHours;
    if (days >= 1) return Lc.current.daysLeft('${days}');
    if (hours >= 1) return Lc.current.hoursLeft('${hours}');
    return Lc.current.expiringSoon;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(Lc.current.recycleBin)),
      body: _items == null
          ? Center(
              child: _failed
                  ? TextButton(
                      onPressed: _load,
                      child: Text(Lc.current.notConnectedTapRetry),
                    )
                  : const CircularProgressIndicator(),
            )
          : _items!.isEmpty
          ? Center(
              child: Text(
                Lc.current.emptyHere,
                style: TextStyle(color: cs.outline),
              ),
            )
          : ListView.builder(
              itemCount: _items!.length,
              itemBuilder: (context, i) {
                final f = _items![i];
                return ListTile(
                  leading: Icon(fileIconFor(f.name), color: cs.outline),
                  title: Text(
                    f.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${bytesText(f.size)} · ${_left(f.expiresIn)}',
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
    );
  }
}
