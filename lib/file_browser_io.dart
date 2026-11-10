import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'cloud.dart';
import 'downloads.dart';
import 'file_pick.dart';
import 'l10n/l10n.dart';
import 'upload_manager.dart';
import 'utils.dart';
import 'widgets/file_card.dart';
import 'widgets/toast.dart';

/// 手机里的文件，自己翻、自己选。
///
/// 用「所有文件访问权限」直接读存储，不走系统选择器：选择器各家 ROM 长得不一样，
/// 有的只认图片和媒体，apk、压缩包、工程文件根本翻不到。
/// 这就是一棵目录树，点进去、选中、传上去。
///
/// 只读：不删、不改、不移动。碰不到的目录（Android/data 这类）直接跳过。

bool get fileBrowserSupported => Platform.isAndroid;

/// 安卓 11 起，就算有「所有文件访问权限」，这两个目录也只给应用自己看。
const _blockedNames = {'Android'};

class FileBrowserPage extends StatefulWidget {
  const FileBrowserPage({
    super.key,
    this.pickOnly = false,
    this.openOnly = false,
    this.initialPath,
    this.highlight,
  });

  /// 只挑不传：选完把文件交回调用方，由它自己决定传不传、传到哪里。
  /// 云盘那边是 false——点一下就直接传上去了。
  final bool pickOnly;

  /// 只看不传：点文件就是打开它。「已下载」和云盘定位都走这个。
  final bool openOnly;

  /// 一进来就站到哪。从云盘点已下载的文件时，直接落到它那层目录。
  final String? initialPath;

  /// 落进去之后给谁打底。文件名，对得上就染一下，省得在一屏里找。
  final String? highlight;

  @override
  State<FileBrowserPage> createState() => _FileBrowserPageState();
}

class _Row {
  _Row({
    required this.name,
    required this.path,
    required this.isDir,
    this.size = 0,
    this.mtime = 0,
    this.blocked = false,
  });

  final String name;
  final String path;
  final bool isDir;
  final int size;
  final int mtime;

  /// 系统不给看内容的目录，点了只提示，不进去。
  final bool blocked;
}

class _FileBrowserPageState extends State<FileBrowserPage>
    with WidgetsBindingObserver {
  List<String> _roots = const [];
  String _path = '';
  List<_Row> _rows = const [];

  bool _noAccess = false;
  bool _loading = true;
  bool _loadFailed = false;

  bool _selecting = false;
  final Set<String> _picked = {};

  bool _uploading = false;

  final TextEditingController _search = TextEditingController();
  final ScrollController _scroll = ScrollController();
  String _q = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check(ask: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    // 权限是在系统设置页里开的，回到前台再确认一次，不用用户手动重进。
    if (s == AppLifecycleState.resumed && _noAccess) {
      _check(ask: false);
    }
  }

  Future<void> _check({required bool ask}) async {
    if (!Platform.isAndroid) {
      if (mounted) {
        setState(() {
          _noAccess = true;
          _loading = false;
        });
      }
      return;
    }
    var st = await Permission.manageExternalStorage.status;
    if (!st.isGranted && ask) {
      st = await Permission.manageExternalStorage.request();
    }
    if (!st.isGranted) {
      // 安卓 10 及以下没有「所有文件访问权限」，普通存储权限给了就能读。
      var s2 = await Permission.storage.status;
      if (!s2.isGranted && ask) s2 = await Permission.storage.request();
      if (s2.isGranted) st = s2;
    }
    if (!mounted) return;
    if (!st.isGranted) {
      setState(() {
        _noAccess = true;
        _loading = false;
      });
      return;
    }
    final roots = await _storageRoots();
    if (!mounted) return;
    setState(() {
      _noAccess = false;
      _roots = roots;
    });
    final start = widget.initialPath;
    if (start != null && start.isNotEmpty && await Directory(start).exists()) {
      await _load(start);
      return;
    }
    await _load(roots.isEmpty ? '/storage/emulated/0' : roots.first);
  }

  /// 内部存储排第一，其他存卡/OTG 跟在后面。
  Future<List<String>> _storageRoots() async {
    final out = <String>['/storage/emulated/0'];
    try {
      await for (final e in Directory('/storage').list(followLinks: false)) {
        if (e is! Directory) continue;
        final name = _base(e.path);
        if (name == 'emulated' || name == 'self') continue;
        out.add(e.path);
      }
    } on FileSystemException {
      // 有的 ROM 不给看 /storage 本身，内部存储那条照样能用
    }
    return out;
  }

  String _base(String p) {
    final t = p.endsWith('/') ? p.substring(0, p.length - 1) : p;
    final i = t.lastIndexOf('/');
    return i < 0 ? t : t.substring(i + 1);
  }

  Future<void> _load(String path) async {
    setState(() {
      _path = path;
      _loading = true;
      _loadFailed = false;
      _q = '';
    });
    _search.clear();
    final rows = <_Row>[];
    try {
      await for (final e in Directory(path).list(followLinks: false)) {
        final name = _base(e.path);
        if (name.isEmpty || name.startsWith('.')) continue;
        final isDir = e is Directory;
        final blocked = isDir && _blockedNames.contains(name);
        var size = 0;
        var mtime = 0;
        if (!isDir) {
          try {
            final st = await e.stat();
            size = st.size;
            mtime = st.modified.millisecondsSinceEpoch ~/ 1000;
          } on FileSystemException {
            continue; // 读不到的文件没必要列出来
          }
        }
        rows.add(
          _Row(
            name: name,
            path: e.path,
            isDir: isDir,
            size: size,
            mtime: mtime,
            blocked: blocked,
          ),
        );
      }
    } on FileSystemException {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
        _rows = const [];
      });
      return;
    }
    rows.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
    _scrollToHighlight(rows);
  }

  /// 进来找的那个文件：估算一下位置，先滚到它附近。估不准也只是差几行。
  void _scrollToHighlight(List<_Row> rows) {
    final want = widget.highlight;
    if (want == null || want.isEmpty) return;
    final i = rows.indexWhere((r) => r.name == want);
    if (i < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final at = (i * 56.0).clamp(0.0, _scroll.position.maxScrollExtent);
      _scroll.animateTo(
        at,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    });
  }

  bool get _atRoot => _roots.isEmpty || _path == _roots.first;

  void _up() {
    if (_path.isEmpty) return;
    final i = _path.lastIndexOf('/');
    if (i <= 0) return;
    _load(_path.substring(0, i));
  }

  /// 返回：里面就先回上一级，到根了才退出页面。
  void _back() {
    if (_atRoot || _path.isEmpty) {
      Navigator.maybePop(context);
      return;
    }
    _up();
  }

  void _enter(_Row r) {
    if (r.blocked) {
      toast(context, Lc.current.systemFolderHidden);
      return;
    }
    _load(r.path);
  }

  /// 打开一个文件：系统里有什么就用什么，打不开就说打不开。
  Future<void> _openFile(String path) async {
    try {
      await openSaved(SavedFile(display: path, path: path));
    } catch (e) {
      if (mounted) toast(context, Lc.current.cantOpenThis(e.toString()));
    }
  }

  void _toggle(_Row r, {bool force = false}) {
    if (r.isDir) {
      _enter(r);
      return;
    }
    if (!_selecting && !force) {
      // 单击一个文件：直接用它，不必先进多选
      if (widget.openOnly) {
        _openFile(r.path);
        return;
      }
      if (widget.pickOnly) {
        _handOff([r.path]);
      } else {
        _uploadAll([r.path]);
      }
      return;
    }
    setState(() {
      _selecting = true;
      if (!_picked.remove(r.path)) _picked.add(r.path);
      if (_picked.isEmpty) _selecting = false;
    });
  }

  void _clearPick() {
    setState(() {
      _picked.clear();
      _selecting = false;
    });
  }

  /// 只挑不传：把路径量一下大小交回调用方。
  Future<void> _handOff(List<String> paths) async {
    if (paths.isEmpty || _uploading) return;
    setState(() => _uploading = true);
    final out = <PickedFile>[];
    for (final p in paths) {
      try {
        final st = await File(p).stat();
        out.add(PickedFile(name: _base(p), size: st.size, path: p));
      } catch (_) {
        // 读不到的就跳过，别让一个坏文件挡住整批
      }
    }
    if (!mounted) return;
    setState(() => _uploading = false);
    if (out.isEmpty) {
      toast(context, Lc.current.uploadSomeFailed('0', '${paths.length}'));
      return;
    }
    Navigator.pop(context, out);
  }

  /// 点一下就交给上传队列，然后立刻退出去。
  /// 原来是在这一页里一个接一个 await 着传，进度只有「第几个」，
  /// 传一个 1GB 的文件时屏幕上永远停在第 1 个，看着就像死了。
  Future<void> _uploadAll(List<String> paths) async {
    if (paths.isEmpty) return;
    final out = <PickedFile>[];
    for (final p in paths) {
      try {
        final st = await File(p).stat();
        out.add(PickedFile(name: _base(p), size: st.size, path: p));
      } catch (_) {
        // 读不到的就跳过，别让一个坏文件挡住整批
      }
    }
    if (!mounted) return;
    if (out.isEmpty) {
      toast(context, Lc.current.uploadSomeFailed('0', '${paths.length}'));
      return;
    }
    UploadManager.i.addAll(out);
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      canPop: _atRoot,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _up();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _back,
            tooltip: Lc.current.back,
          ),
          title: _selecting
              ? Text(Lc.current.pickedCount('${_picked.length}'))
              : Text(
                  _titleText(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
          actions: [
            if (_selecting)
              TextButton(onPressed: _clearPick, child: Text(Lc.current.cancel))
            else
              IconButton(
                tooltip: Lc.current.refresh,
                icon: const Icon(Icons.refresh),
                onPressed: _path.isEmpty ? null : () => _load(_path),
              ),
          ],
        ),
        floatingActionButton: _selecting && _picked.isNotEmpty && !_uploading
            ? FloatingActionButton.extended(
                onPressed: () => widget.pickOnly
                    ? _handOff(_picked.toList())
                    : _uploadAll(_picked.toList()),
                icon: Icon(widget.pickOnly ? Icons.check : Icons.upload_file),
                label: Text(
                  widget.pickOnly
                      ? Lc.current.cloudPickDone('${_picked.length}')
                      : Lc.current.uploadPicked('${_picked.length}'),
                ),
              )
            : null,
        body: _body(cs),
      ),
    );
  }

  String _titleText() {
    if (_path.isEmpty) return Lc.current.storageRoot;
    if (_roots.isNotEmpty && _path == _roots.first) {
      return Lc.current.storageRoot;
    }
    return _base(_path);
  }

  Widget _body(ColorScheme cs) {
    if (_noAccess) return _noAccessView(cs);
    return Column(
      children: [
        if (!_selecting) _crumbs(cs),
        if (!_selecting) _searchBar(cs),
        Expanded(child: _list(cs)),
      ],
    );
  }

  Widget _noAccessView(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_off_outlined, size: 44, color: cs.outline),
          const SizedBox(height: 14),
          Text(
            Lc.current.allFilesAccess,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            Lc.current.allFilesWhy,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: () async {
              await openAppSettings();
            },
            child: Text(Lc.current.allFilesOpen),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () => _check(ask: true),
            child: Text(Lc.current.allFilesRetry),
          ),
        ],
      ),
    );
  }

  Widget _crumbs(ColorScheme cs) {
    if (_path.isEmpty) return const SizedBox.shrink();
    // 根目录不拆开显示。真按路径拆，「存储」后面还会跟一行 storage > emulated > 0，
    // 层层点进去本来也是同一个地方，白占一整行。
    var base = _roots.isEmpty ? '' : _roots.first;
    for (final r in _roots) {
      if (_path == r || _path.startsWith('$r/')) {
        base = r;
        break;
      }
    }
    final rel = base.isNotEmpty && _path.startsWith(base)
        ? _path.substring(base.length)
        : _path;
    final parts = rel.split('/').where((s) => s.isNotEmpty).toList();
    final items = <Widget>[];
    var acc = base;
    items.add(
      InkWell(
        onTap: base.isEmpty ? null : () => _load(base),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Text(
            base == (_roots.isEmpty ? '' : _roots.first)
                ? Lc.current.storageRoot
                : _base(base),
            style: TextStyle(fontSize: 12.5, color: cs.primary),
          ),
        ),
      ),
    );
    for (var i = 0; i < parts.length; i++) {
      final p = parts[i];
      acc += '/$p';
      final target = acc;
      final last = i == parts.length - 1;
      items.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chevron_right, size: 14, color: cs.outline),
            InkWell(
              onTap: last ? null : () => _load(target),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                child: Text(
                  p,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: last ? cs.onSurfaceVariant : cs.primary,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return SizedBox(
      height: 26,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: items),
      ),
    );
  }

  Widget _searchBar(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: SizedBox(
        height: 36,
        child: TextField(
          autocorrect: false,
          enableSuggestions: false,
          controller: _search,
          onChanged: (v) => setState(() => _q = v),
          textAlignVertical: TextAlignVertical.center,
          style: const TextStyle(fontSize: 13.5),
          decoration: InputDecoration(
            isDense: true,
            hintText: Lc.current.searchThisFolder,
            prefixIcon: const Icon(Icons.search, size: 17),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 34,
              minHeight: 34,
            ),
            filled: true,
            fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
            contentPadding: const EdgeInsets.symmetric(vertical: 7),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ),
    );
  }

  Widget _list(ColorScheme cs) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_loadFailed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              Lc.current.noAccessFolder,
              style: TextStyle(color: cs.outline),
            ),
            const SizedBox(height: 6),
            TextButton(onPressed: _up, child: Text(Lc.current.back)),
          ],
        ),
      );
    }
    final kw = _q.trim().toLowerCase();
    final showShortcuts = _atRoot && kw.isEmpty;
    final rows = kw.isEmpty
        ? _rows
        : _rows.where((r) => r.name.toLowerCase().contains(kw)).toList();
    if (rows.isEmpty) {
      return Center(
        child: Text(
          kw.isEmpty ? Lc.current.folderEmpty : Lc.current.notFound,
          style: TextStyle(color: cs.outline),
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      itemCount: rows.length + (showShortcuts ? 1 : 0),
      itemBuilder: (context, i) {
        if (showShortcuts && i == 0) return _shortcuts(cs);
        final r = rows[i - (showShortcuts ? 1 : 0)];
        return _rowTile(r, cs);
      },
    );
  }

  /// 根目录顶上一排常用的，省得一层层往下点。
  Widget _shortcuts(ColorScheme cs) {
    const names = [
      'Download',
      'DCIM',
      'Pictures',
      'Documents',
      'Music',
      'Movies',
    ];
    final have = _rows.where((r) => r.isDir).map((r) => r.name).toSet();
    final items = [
      for (final n in names)
        if (have.contains(n))
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ActionChip(
              label: Text(n, style: const TextStyle(fontSize: 12)),
              visualDensity: VisualDensity.compact,
              onPressed: () => _load('$_path/$n'),
            ),
          ),
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
      child: Row(children: items),
    );
  }

  Widget _rowTile(_Row r, ColorScheme cs) {
    final picked = _picked.contains(r.path);
    final marked = widget.highlight != null && r.name == widget.highlight;
    return ListTile(
      dense: true,
      selected: picked,
      tileColor: marked ? cs.primaryContainer.withValues(alpha: 0.4) : null,
      leading: _selecting && !r.isDir
          ? Icon(
              picked ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 22,
              color: picked ? cs.primary : cs.outline,
            )
          : Icon(
              r.isDir
                  ? (r.blocked ? Icons.lock_outline : Icons.folder)
                  : fileIconFor(r.name),
              size: 24,
              color: r.isDir ? cs.primary : cs.onSurfaceVariant,
            ),
      title: Text(
        r.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14),
      ),
      subtitle: r.isDir
          ? null
          : Text(
              [
                bytesText(r.size),
                if (r.mtime > 0) timeAgo(r.mtime),
              ].join(' · '),
              style: TextStyle(fontSize: 11.5, color: cs.outline),
            ),
      trailing: r.isDir
          ? Icon(Icons.chevron_right, size: 18, color: cs.outline)
          : null,
      onTap: () => _toggle(r),
      // 只看不传的模式下不给多选：这里没有「上传」这一步可做
      onLongPress: r.isDir || widget.openOnly
          ? null
          : () => _toggle(r, force: true),
    );
  }
}
