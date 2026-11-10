import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../cloud.dart';
import '../download_index.dart';
import '../download_manager.dart';
import '../downloads.dart';
import '../file_browser.dart';
import '../local_files.dart';
import '../l10n/l10n.dart';
import '../utils.dart';
import '../widgets/empty_view.dart';
import '../widgets/app_sheet.dart';
import '../widgets/file_card.dart';
import '../widgets/page_width.dart';
import '../widgets/toast.dart';

/// 已下载：手机里那些从站里存下来的文件。
///
/// 只管本地这一份。删了不影响云盘，云盘删了这里也还在。
/// 点一下打开，长按能删、能去文件所在的那层目录看看。
class DownloadsPage extends StatefulWidget {
  const DownloadsPage({super.key, this.embedded = false});

  /// 塞进「传输」页的 tab 里时不再自带 AppBar。
  final bool embedded;

  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _Entry {
  _Entry(this.rec, this.path);

  final LocalDownload rec;

  /// 真的还在的话，打开/定位都用它。
  final String? path;

  bool get alive => path != null;
}

class _DownloadsPageState extends State<DownloadsPage> {
  List<_Entry> _items = const [];
  bool _loading = true;
  bool _noAccess = false;

  /// 多选：进了选择模式，点条目是勾选，不再打开文件。
  bool _selecting = false;
  final Set<String> _sel = <String>{};

  /// 已经在下几个。下完一个就少一个，靠这个数目变少判断该刷新列表了。
  int _dlCount = 0;

  @override
  void initState() {
    super.initState();
    _dlCount = DownloadManager.i.jobs.length;
    DownloadManager.i.addListener(_onDl);
    _load();
  }

  @override
  void dispose() {
    DownloadManager.i.removeListener(_onDl);
    super.dispose();
  }

  /// 传送页里正在下的下完一个，列表底下就该多出一条。
  void _onDl() {
    final n = DownloadManager.i.jobs.length;
    final finished = n < _dlCount;
    _dlCount = n;
    if (finished && mounted) _load();
  }

  /// 读下载目录得先有权限。没给就先问，问不到就让页面上留个按钮。
  Future<bool> _ensureAccess({bool ask = true}) async {
    if (!fileBrowserSupported) return true;
    var st = await Permission.manageExternalStorage.status;
    if (!st.isGranted && ask) {
      st = await Permission.manageExternalStorage.request();
    }
    if (!st.isGranted) {
      var s2 = await Permission.storage.status;
      if (!s2.isGranted && ask) s2 = await Permission.storage.request();
      if (s2.isGranted) st = s2;
    }
    return st.isGranted;
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    if (fileBrowserSupported && !await _ensureAccess()) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _noAccess = true;
      });
      return;
    }
    if (mounted) setState(() => _noAccess = false);
    final recs = [...await loadLocalDownloads()];
    // 扫一遍默认目录，把老版本下载、没留记录的也算进来。
    final seen = recs.map((e) => e.display).toSet();
    for (final r in await scanDownloadDir()) {
      if (seen.add(r.display)) recs.add(r);
    }
    recs.sort((a, b) => b.at.compareTo(a.at));
    final items = <_Entry>[];
    for (final r in recs) {
      items.add(_Entry(r, await localFileOf(r)));
    }
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _open(_Entry e) async {
    final p = e.path;
    if (p == null) {
      toast(context, Lc.current.localFileGone);
      return;
    }
    try {
      await openSaved(SavedFile(display: p, path: p));
    } catch (err) {
      if (mounted) toast(context, Lc.current.cantOpenThis('$err'));
    }
  }

  /// 去文件所在的那层目录。里面再点才是打开。
  Future<void> _reveal(_Entry e) async {
    final p = e.path;
    if (p == null) {
      toast(context, Lc.current.localFileGone);
      return;
    }
    final cut = p.lastIndexOf('/');
    if (cut <= 0) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FileBrowserPage(
          openOnly: true,
          initialPath: p.substring(0, cut),
          highlight: p.substring(cut + 1),
        ),
      ),
    );
  }

  Future<void> _deleteLocal(_Entry e) async {
    final p = e.path;
    if (p == null) {
      await forgetLocalDownload(e.rec.display);
      _load();
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(e.rec.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        content: Text(Lc.current.deleteLocalAsk),
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
    final done = await deleteLocalFile(p);
    if (!done) {
      if (mounted) toast(context, Lc.current.localFileGone);
      return;
    }
    await forgetLocalDownload(e.rec.display);
    if (mounted) {
      setState(
        () =>
            _items = [..._items]
              ..removeWhere((x) => x.rec.display == e.rec.display),
      );
    }
  }

  Future<void> _removeRecord(_Entry e) async {
    await forgetLocalDownload(e.rec.display);
    if (mounted) {
      setState(
        () =>
            _items = [..._items]
              ..removeWhere((x) => x.rec.display == e.rec.display),
      );
    }
  }

  Future<void> _clearMissing() async {
    final gone = _items.where((e) => !e.alive).toList();
    if (gone.isEmpty) return;
    await forgetLocalDownloads(gone.map((e) => e.rec.display));
    if (mounted) {
      setState(() => _items = _items.where((e) => e.alive).toList());
    }
  }

  void _startSelect({String? pick}) {
    setState(() {
      _selecting = true;
      _sel
        ..clear()
        ..addAll([?pick]);
    });
  }

  void _endSelect() {
    setState(() {
      _selecting = false;
      _sel.clear();
    });
  }

  void _toggle(String display) {
    setState(() {
      if (!_sel.remove(display)) _sel.add(display);
    });
  }

  /// 全选 / 全不选。已经全选了就反过来。
  void _toggleAll() {
    final all = _items.map((e) => e.rec.display).toList();
    setState(() {
      if (_sel.length == all.length) {
        _sel.clear();
      } else {
        _sel
          ..clear()
          ..addAll(all);
      }
    });
  }

  /// 一次删掉勾上的那些。
  ///
  /// 默认只清列表，手机里的文件留着；弹窗里勾了「同时删除已下载的文件」
  /// 才连文件一起删。
  Future<void> _deleteSelected() async {
    final picked = _items.where((e) => _sel.contains(e.rec.display)).toList();
    if (picked.isEmpty) return;
    var withFile = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(Lc.current.delete),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                picked.length == 1
                    ? Lc.current.deleteTaskAsk
                    : Lc.current.deleteTasksAskN(picked.length),
              ),
              const SizedBox(height: 6),
              InkWell(
                onTap: () => setLocal(() => withFile = !withFile),
                child: Row(
                  children: [
                    Checkbox(
                      value: withFile,
                      visualDensity: VisualDensity.compact,
                      onChanged: (v) => setLocal(() => withFile = v ?? false),
                    ),
                    Flexible(
                      child: Text(
                        Lc.current.alsoDeleteFile,
                        style: const TextStyle(fontSize: 13.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(Lc.current.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(Lc.current.confirm),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final done = <String>{};
    for (final e in picked) {
      final p = e.path;
      // 文件已经被人挪走的，删不动也无所谓，记录照样清掉。
      if (withFile && p != null) await deleteLocalFile(p);
      await forgetLocalDownload(e.rec.display);
      done.add(e.rec.display);
    }
    if (!mounted) return;
    setState(() {
      _items = _items.where((e) => !done.contains(e.rec.display)).toList();
      _selecting = false;
      _sel.clear();
    });
    toast(
      context,
      withFile
          ? Lc.current.deletedSelected(done.length)
          : Lc.current.clearedFromList(done.length),
    );
  }

  void _menu(_Entry e) {
    final cs = Theme.of(context).colorScheme;
    showAppSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (e.alive)
              ListTile(
                leading: const Icon(Icons.folder_open_outlined),
                title: Text(Lc.current.showInFolder),
                onTap: () {
                  Navigator.pop(ctx);
                  _reveal(e);
                },
              ),
            if (e.alive)
              ListTile(
                leading: Icon(Icons.delete_outline, color: cs.error),
                title: Text(
                  Lc.current.deleteLocalFile,
                  style: TextStyle(color: cs.error),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteLocal(e);
                },
              )
            else
              ListTile(
                leading: const Icon(Icons.playlist_remove),
                title: Text(Lc.current.removeFromList),
                onTap: () {
                  Navigator.pop(ctx);
                  _removeRecord(e);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasMissing = _items.any((e) => !e.alive);
    final canSelect = _items.isNotEmpty;
    final allOn = canSelect && _sel.length == _items.length;
    if (widget.embedded) {
      // 没有自己的 AppBar，多选那几条操作挪到页面顶上一条细栏里，
      // 平时不占地方，进了选择模式才出现。
      return PageWidth(
        child: Column(
          children: [
            if (_selecting)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: _endSelect,
                      tooltip: Lc.current.cancel,
                    ),
                    Expanded(
                      child: Text(
                        Lc.current.selectedCount(_sel.length),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      tooltip: allOn
                          ? Lc.current.selectNone
                          : Lc.current.selectAll,
                      icon: Icon(allOn ? Icons.deselect : Icons.select_all),
                      onPressed: canSelect ? _toggleAll : null,
                    ),
                    IconButton(
                      tooltip: Lc.current.deleteSelected,
                      icon: const Icon(Icons.delete_outline),
                      onPressed: _sel.isEmpty ? null : _deleteSelected,
                    ),
                  ],
                ),
              ),
            Expanded(
              child: RefreshIndicator(onRefresh: _load, child: _body()),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        leading: _selecting
            ? IconButton(icon: const Icon(Icons.close), onPressed: _endSelect)
            : null,
        title: Text(
          _selecting
              ? Lc.current.selectedCount(_sel.length)
              : Lc.current.downloadsPage,
        ),
        actions: [
          if (_selecting) ...[
            IconButton(
              tooltip: allOn ? Lc.current.selectNone : Lc.current.selectAll,
              icon: Icon(allOn ? Icons.deselect : Icons.select_all),
              onPressed: canSelect ? _toggleAll : null,
            ),
            IconButton(
              tooltip: Lc.current.deleteSelected,
              icon: const Icon(Icons.delete_outline),
              onPressed: _sel.isEmpty ? null : _deleteSelected,
            ),
          ] else ...[
            if (canSelect)
              IconButton(
                tooltip: Lc.current.selectMode,
                icon: const Icon(Icons.checklist),
                onPressed: _startSelect,
              ),
            if (hasMissing)
              IconButton(
                tooltip: Lc.current.clearMissingRecords,
                icon: const Icon(Icons.cleaning_services_outlined),
                onPressed: _clearMissing,
              ),
          ],
        ],
      ),
      body: PageWidth(
        child: RefreshIndicator(onRefresh: _load, child: _body()),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_noAccess) {
      return EmptyView(
        icon: Icons.folder_off_outlined,
        title: Lc.current.allFilesAccess,
        hint: Lc.current.allFilesWhy,
        action: FilledButton(
          onPressed: () async {
            await _ensureAccess();
            _load();
          },
          child: Text(Lc.current.allFilesOpen),
        ),
      ).scrollable();
    }
    if (!fileBrowserSupported) {
      return EmptyView(
        icon: Icons.download_outlined,
        title: Lc.current.downloadsPage,
        hint: Lc.current.downloadsByBrowser,
      ).scrollable();
    }
    if (_items.isEmpty) {
      return EmptyView(
        icon: Icons.download_outlined,
        title: Lc.current.downloadsEmpty,
      ).scrollable();
    }
    final alive = _items.where((e) => e.alive).length;
    final bytes = _items.fold<int>(0, (s, e) => s + e.rec.size);
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: _items.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Text(
              Lc.current.downloadsCount('$alive', bytesText(bytes)),
              style: TextStyle(
                fontSize: 12.5,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          );
        }
        final e = _items[i - 1];
        return _tile(e);
      },
    );
  }

  Widget _tile(_Entry e) {
    final cs = Theme.of(context).colorScheme;
    final picked = _sel.contains(e.rec.display);
    final sub = <String>[
      if (e.rec.size > 0) bytesText(e.rec.size),
      if (e.rec.at > 0) timeAgo(e.rec.at),
      if (!e.alive) Lc.current.localFileGone,
    ];
    return ListTile(
      leading: _selecting
          ? Checkbox(value: picked, onChanged: (_) => _toggle(e.rec.display))
          : Icon(
              fileIconFor(e.rec.name),
              size: 24,
              color: e.alive ? cs.onSurfaceVariant : cs.outlineVariant,
            ),
      selected: _selecting && picked,
      title: Text(
        e.rec.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 14.5, color: e.alive ? null : cs.outline),
      ),
      subtitle: Text(
        sub.join(' · '),
        style: TextStyle(fontSize: 11.5, color: cs.outline),
      ),
      trailing: _selecting
          ? null
          : IconButton(
              tooltip: Lc.current.more,
              icon: const Icon(Icons.more_vert, size: 18),
              color: cs.outline,
              onPressed: () => _menu(e),
            ),
      onTap: _selecting
          ? () => _toggle(e.rec.display)
          : () => e.alive ? _open(e) : _menu(e),
      // 长按出多选，顺手把这条勾上。要删就再点上面那个删除。
      onLongPress: _selecting ? null : () => _startSelect(pick: e.rec.display),
    );
  }
}
