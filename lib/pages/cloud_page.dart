import 'package:flutter/material.dart';

import '../api.dart';
import '../cloud.dart';
import '../file_open.dart';
import '../file_pick.dart';
import '../l10n/error_text.dart';
import '../utils.dart';
import '../widgets/file_card.dart';

import '../l10n/l10n.dart';
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
      final p = await CloudApi.list(q: _q, sort: _sort, page: 1, perPage: _perPage);
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
          q: _q, sort: _sort, page: _page + 1, perPage: _perPage);
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _open(CloudFile f) async {
    try {
      final url = f.url.startsWith('http') ? f.url : '${Api.base}${f.url}';
      await openRemoteFile(url, f.name);
    } catch (e) {
      if (mounted) _toast(errorText(context, e));
    }
  }

  Future<void> _delete(CloudFile f) async {
    final used = f.refs;
    final trashHint = Lc.current.goesToTrashHint;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Lc.current.deleteThisFile),
        content: Text(used > 0
            ? '${Lc.current.cloudRefsWarn('$used')}\n\n$trashHint'
            : trashHint),
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
        onPressed: _uploading ? null : _upload,
        icon: _uploading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.upload_file),
        label: Text(Lc.current.upload),
      ),
      body: RefreshIndicator(
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
      return ListView(
        children: [
          const SizedBox(height: 100),
          Center(
            child: Text(
              _q.isEmpty ? Lc.current.nothingUploadedYet : Lc.current.notFound,
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ),
        ],
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
          onMenu: () => _menu(f),
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
                usage.unlimited ? Lc.current.usedSpace('${usedText}') : Lc.current.usedOfTotal('${usedText}', '${quotaText}'),
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
                  prefixIconConstraints:
                      const BoxConstraints(minWidth: 36, minHeight: 36),
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
    required this.onMenu,
  });

  final CloudFile file;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final refs = file.refs;
    final sub = StringBuffer(bytesText(file.size));
    if (file.createdAt > 0) sub.write(' · ${timeAgo(file.createdAt)}');
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
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
                  const SizedBox(height: 2),
                  Text(
                    sub.toString(),
                    style: TextStyle(fontSize: 12, color: cs.outline),
                  ),
                  if (file.refs > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        Lc.current.usedByPosts('${refs}'),
                        style: TextStyle(fontSize: 11.5, color: cs.primary),
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.more_vert, size: 20),
              onPressed: onMenu,
            ),
          ],
        ),
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(Lc.current.restoredDone)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(errorText(context, e))));
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
                  ? TextButton(onPressed: _load, child: Text(Lc.current.notConnectedTapRetry))
                  : const CircularProgressIndicator())
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
                      subtitle: Text('${bytesText(f.size)} · ${_left(f.expiresIn)}'),
                      trailing: TextButton(
                        onPressed: () => _restore(f),
                        child: Text(Lc.current.restore),
                      ),
                    );
                  },
                ),
    );
  }
}
