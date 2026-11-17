import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'cancel_token.dart';
import 'downloads_common.dart' show sizeText;
import 'manga.dart';
import 'manga_dl.dart';
import 'store.dart';

/// 漫画离线下载。
///
/// 服务器上有两万本，手机上原本一本都没有：一进地铁，书架点开就是一片裂图。
/// 这里把「整话」和「整本未读」下到 `<appSupport>/manga/<站点>/` 下，
/// 阅读器取页时先看本地，没有才走网络。
///
/// 几个刻意的取舍：
/// - **只下内部书源的书**（书架里那些）。书源的图是源站现取的、地址会过期，
///   存下来过几天就是一堆打不开的文件，白占地方。
/// - **索引只存文件名，不存带域名的绝对地址**。站点一换域名，存了绝对地址的
///   索引全废；存 `001.jpg` 这种，换个站还是这一批文件。
/// - **索引和阅读位置是两套 key**，别混：位置是「读到哪」，索引是「下到哪」。
class MangaDown extends ChangeNotifier {
  MangaDown._();

  static final MangaDown i = MangaDown._();

  /// 网页版没有落盘这回事，界面上就别摆下载按钮。
  bool get supported => mangaDlOk;

  /// 一本书下好了多少话。
  final Map<String, MangaDlBook> _books = {};

  /// 正在下的书，键是书目录。
  final Map<String, MangaDlJob> _jobs = {};

  final List<_Task> _q = [];
  int _busy = 0;

  static const _maxWorkers = 2;

  String _site = '';
  String _root = '';
  bool _ready = false;

  /// 索引动过几次。列表靠它知道该重画了。
  int _epoch = 0;
  int get epoch => _epoch;

  /// 上一批任务收尾时的一句话，给页面捞走弹一次。
  String? lastDone;
  void clearLastDone() => lastDone = null;

  // ---------------------------------------------------------------- 加载

  Future<void>? _loading;

  Future<void> init() async {
    if (!mangaDlOk) return;
    // 站点一切换就是另一个目录：不挂这个，A 站下的书会在 B 站的书架上
    // 挂着「离线」标记，点开却是空的。启动时那份默认值也靠它纠正过来
    // （main 里 init 比设置读盘早一步，那时 activeKey 还是空的）。
    if (!_hooked) {
      _hooked = true;
      AppState.instance.addListener(_onSite);
    }
    final site = _siteKey();
    if (_ready && site == _site) return;
    final running = _loading;
    if (running != null && site == _site) {
      await running;
      return;
    }
    _site = site;
    _loading = _load(site);
    try {
      await _loading;
    } finally {
      _loading = null;
    }
  }

  bool _hooked = false;

  void _onSite() {
    if (!_ready || _loading != null) return;
    if (_siteKey() == _site) return;
    unawaited(init());
  }

  String _siteKey() {
    final st = AppState.instance;
    final k = st.activeKey.isEmpty ? 'default' : st.activeKey;
    return k;
  }

  Future<void> _load(String site) async {
    _root = await mangaDlRoot(site);
    _books.clear();
    final raw = await mangaDlReadIndex(_root);
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final m = jsonDecode(raw);
        final books = (m is Map ? (m['books'] as Map?) : null) ?? const {};
        books.forEach((k, v) {
          final b = MangaDlBook.fromJson('$k', v);
          if (b != null) _books['$k'] = b;
        });
      } catch (_) {
        // 索引坏了：挪到一边留个现场，当没下过。书架上的「离线」标记会消失，
        // 重新下一话就又是一条完整的索引——不崩、不卡在这里。
        await mangaDlQuarantineIndex(_root);
        _books.clear();
      }
    }
    _ready = true;
    _bump();
  }

  void _bump() {
    _epoch++;
    notifyListeners();
  }

  Future<void> _save() async {
    if (!mangaDlOk || _root.isEmpty) return;
    try {
      await mangaDlWriteIndex(
        _root,
        jsonEncode({
          'version': 1,
          'books': {for (final e in _books.entries) e.key: e.value.toJson()},
        }),
      );
    } catch (_) {
      // 写不进去（空间满、被系统锁）就先留着内存里这份，下一话再试
    }
  }

  // ---------------------------------------------------------------- 查询

  MangaDlBook? book(String dir) => _books[dir];

  /// 本机存着的那些书，最近下的在前。
  List<MangaDlBook> get offlineBooks {
    final out = _books.values.toList()
      ..sort((a, b) => b.at.compareTo(a.at));
    return out;
  }

  /// 正在下的那几本。
  List<MangaDlJob> get jobs => List.unmodifiable(_jobs.values);

  bool isChapterOffline(String dir, String chDir) =>
      _books[dir]?.chapters[chDir] != null;

  int offlineChapters(String dir) => _books[dir]?.chapters.length ?? 0;

  int bytesOf(String dir) => _books[dir]?.bytes ?? 0;

  /// 这本书要的几话全在本机了。
  bool bookFullyOffline(String dir) {
    final b = _books[dir];
    if (b == null || b.total <= 0) return false;
    return b.chapters.length >= b.total;
  }

  /// 正在下的那本书的进度，没在动就是 null。
  MangaDlJob? jobOf(String dir) => _jobs[dir];

  /// 这一话每一页在本机的路径，没下过的位置是 null。按页序对，别按文件名猜。
  List<String?> localPages(String dir, String chDir, int count) {
    final ch = _books[dir]?.chapters[chDir];
    if (ch == null || _root.isEmpty) return List<String?>.filled(count, null);
    return [
      for (var i = 0; i < count; i++)
        i < ch.files.length ? '$_root/$dir/$chDir/${ch.files[i]}' : null,
    ];
  }

  /// 第 i 页（0 基）在本机的话给路径。
  String? localPageAt(String dir, String chDir, int i) {
    final ch = _books[dir]?.chapters[chDir];
    if (ch == null || i < 0 || i >= ch.files.length || _root.isEmpty) return null;
    return '$_root/$dir/$chDir/${ch.files[i]}';
  }

  // ---------------------------------------------------------------- 开下

  /// 一话按几张图估。服务端给了页数就不猜。
  int estimateBytes(List<MangaChapter> chs) {
    var pages = 0;
    for (final c in chs) {
      pages += c.pages > 0 ? c.pages : 18;
    }
    // 300 KB 一张是这套源的实测均值，压得挺狠
    return pages * 300 * 1024;
  }

  /// 开下之前先看一眼空间。够就是 null，不够给一句人话。
  Future<String?> spaceWarn(int need) async {
    if (!mangaDlOk) return null;
    final free = await mangaDlFreeBytes();
    if (free < 0) return null;
    if (free >= need) return null;
    return '空间不够：预计要 ${sizeText(need)}，只剩 ${sizeText(free)}';
  }

  /// 下这几话。[unreadOnly] 只下没下过的（页面上「下载未读」就是这个）。
  Future<MangaEnqueueResult> download(
    MangaDetail d,
    List<MangaChapter> chs, {
    bool unreadOnly = true,
  }) async {
    if (!mangaDlOk) {
      return const MangaEnqueueResult(0, 0, '网页版不支持离线下载');
    }
    await init();
    final job = _jobs[d.dir];
    final targets = [
      for (final c in chs)
        if (!isChapterOffline(d.dir, c.dir) && !(job?.has(c.dir) ?? false)) c,
    ];
    final skipped = chs.length - targets.length;
    if (targets.isEmpty) return MangaEnqueueResult(0, skipped, null);

    // 一次排两万本会把队列撑爆，也让「取消」变成按不完的键。
    final warn = await spaceWarn(estimateBytes(targets));
    if (warn != null) return MangaEnqueueResult(0, skipped, warn);

    final j = job ??
        (_jobs[d.dir] = MangaDlJob(
          dir: d.dir,
          title: d.title,
          chaptersTotal: 0,
        ));
    for (final c in targets) {
      j.chaptersTotal++;
      j.pending++;
      j.mark(c.dir);
      _q.add(_Task(detail: d, ch: c, job: j));
    }
    _bump();
    _pump();
    return MangaEnqueueResult(targets.length, skipped, null);
  }

  /// 整本没下过的都排上。中途能取消。
  Future<MangaEnqueueResult> downloadUnread(MangaDetail d) =>
      download(d, d.chapters);

  void cancelBook(String dir) {
    final j = _jobs.remove(dir);
    _q.removeWhere((t) => t.job.dir == dir);
    if (j == null) return;
    j.cancelled = true;
    j.token.cancel();
    lastDone = '${j.title}：已取消，下到一半的话保留，下次接着下';
    _bump();
  }

  // ---------------------------------------------------------------- 跑

  void _pump() {
    while (_busy < _maxWorkers && _q.isNotEmpty) {
      final t = _q.removeAt(0);
      _busy++;
      unawaited(_run(t).whenComplete(() {
        _busy--;
        _pump();
      }));
    }
  }

  Future<void> _run(_Task t) async {
    final job = t.job;
    if (job.cancelled) {
      _finish(job, t);
      return;
    }
    final dir = t.detail.dir;
    final chDir = t.ch.dir;
    try {
      final pages = await MangaApi.pages(dir, chDir);
      if (pages.isEmpty) throw StateError('这一话没有图');
      final names = [
        for (var i = 0; i < pages.length; i++) _nameFor(pages[i], i),
      ];
      final base = job.pagesDone;
      job.pagesTotal += pages.length;
      _bump();
      await mangaDlFetchChapter(
        destDir: '$_root/$dir/$chDir',
        urls: pages,
        names: names,
        cancel: job.token,
        onPage: (done, _) {
          job.pagesDone = base + done;
          _bump();
        },
      );
      if (job.cancelled) {
        _finish(job, t);
        return;
      }
      // 落到索引上。字节数按文件实际大小重算一遍：续传时写进去的
      // 只是这轮新增的那部分，用它当总量会少算。
      var size = 0;
      for (final n in names) {
        size += await mangaDlSize('$_root/$dir/$chDir/$n');
      }
      final b = _books.putIfAbsent(
        dir,
        () => MangaDlBook(
          dir: dir,
          title: t.detail.title,
          cover: t.detail.cover,
        ),
      );
      b.title = t.detail.title;
      b.cover = t.detail.cover;
      if (t.detail.chapters.isNotEmpty) b.total = t.detail.chapters.length;
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      b.at = now;
      b.chapters[chDir] = MangaDlChapter(
        pages: pages.length,
        bytes: size,
        at: now,
        files: names,
      );
      b.bytes = b.chapters.values.fold(0, (a, c) => a + c.bytes);
      await _save();
      job.chaptersDone++;
    } catch (e) {
      if (!job.cancelled) job.failed++;
    }
    _finish(job, t);
  }

  void _finish(MangaDlJob job, _Task t) {
    job.unmark(t.ch.dir);
    job.pending--;
    if (job.pending > 0) {
      _bump();
      return;
    }
    _jobs.remove(job.dir);
    if (job.cancelled) {
      // 取消时 cancelBook 已经写过那句提示了
    } else if (job.failed > 0) {
      lastDone = '${job.title}：${job.chaptersDone} 话下好了，${job.failed} 话失败';
    } else {
      lastDone = '${job.title}：${job.chaptersDone} 话已离线';
    }
    _bump();
  }

  String _nameFor(String url, int i) {
    final n = (i + 1).toString().padLeft(3, '0');
    return '$n${_extOf(url)}';
  }

  String _extOf(String u) {
    final p = Uri.tryParse(u)?.path ?? u;
    final m = RegExp(r'\.(jpe?g|png|webp|gif|bmp)$', caseSensitive: false)
        .firstMatch(p);
    return m == null ? '.img' : m.group(0)!.toLowerCase();
  }

  // ---------------------------------------------------------------- 删

  Future<void> deleteBook(String dir) async {
    cancelBook(dir);
    await init();
    final b = _books.remove(dir);
    if (_root.isNotEmpty) await mangaDlRemoveTree('$_root/$dir');
    if (b != null) await _save();
    _bump();
  }

  Future<void> deleteChapters(String dir, List<String> chDirs) async {
    await init();
    final b = _books[dir];
    if (b == null) return;
    var touched = false;
    for (final chDir in chDirs) {
      if (b.chapters.remove(chDir) == null) continue;
      touched = true;
      if (_root.isNotEmpty) await mangaDlRemoveTree('$_root/$dir/$chDir');
    }
    if (!touched) return;
    if (b.chapters.isEmpty) {
      _books.remove(dir);
      if (_root.isNotEmpty) await mangaDlRemoveTree('$_root/$dir');
    } else {
      b.bytes = b.chapters.values.fold(0, (a, c) => a + c.bytes);
    }
    await _save();
    _bump();
  }
}

class MangaEnqueueResult {
  const MangaEnqueueResult(this.queued, this.skipped, this.error);

  final int queued;
  final int skipped;
  final String? error;
}

/// 一起任务：一话。并发 2，页内串行。
class _Task {
  _Task({required this.detail, required this.ch, required this.job});

  final MangaDetail detail;
  final MangaChapter ch;
  final MangaDlJob job;
}

class MangaDlJob {
  MangaDlJob({
    required this.dir,
    required this.title,
    required this.chaptersTotal,
  });

  final String dir;
  final String title;

  /// 这一批要下几话（排进来以后还会加）。
  int chaptersTotal;
  int chaptersDone = 0;
  int failed = 0;

  /// 已经排进来、还没跑完的话数。
  int pending = 0;

  int pagesTotal = 0;
  int pagesDone = 0;

  bool cancelled = false;
  final CancelToken token = CancelToken();

  final Set<String> _tracked = {};

  bool has(String chDir) => _tracked.contains(chDir);
  void mark(String chDir) => _tracked.add(chDir);
  void unmark(String chDir) => _tracked.remove(chDir);

  /// 按页算；一页都还没取到时退回按话算。
  double get progress {
    if (pagesTotal > 0) return (pagesDone / pagesTotal).clamp(0.0, 1.0);
    if (chaptersTotal > 0) {
      return (chaptersDone / chaptersTotal).clamp(0.0, 1.0);
    }
    return 0;
  }
}

class MangaDlChapter {
  MangaDlChapter({
    this.pages = 0,
    this.bytes = 0,
    this.at = 0,
    this.files = const [],
  });

  final int pages;
  final int bytes;
  final int at;

  /// 这一话每页的文件名，按页序。索引里只存文件名，不存 URL。
  final List<String> files;

  Map<String, Object?> toJson() =>
      {'pages': pages, 'bytes': bytes, 'at': at, 'files': files};

  static MangaDlChapter? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final files = <String>[];
    final fs = raw['files'];
    if (fs is List) {
      for (final f in fs) {
        if (f is String && f.isNotEmpty) files.add(f);
      }
    }
    if (files.isEmpty) return null;
    return MangaDlChapter(
      pages: (raw['pages'] as num?)?.toInt() ?? files.length,
      bytes: (raw['bytes'] as num?)?.toInt() ?? 0,
      at: (raw['at'] as num?)?.toInt() ?? 0,
      files: files,
    );
  }
}

class MangaDlBook {
  MangaDlBook({
    required this.dir,
    required this.title,
    this.cover = '',
    this.total = 0,
    this.at = 0,
    Map<String, MangaDlChapter>? chapters,
  }) : chapters = chapters ?? <String, MangaDlChapter>{};

  final String dir;
  String title;
  String cover;

  /// 这本书一共几话（下的时候记下来的），用来判断「整本离线」。
  int total;
  int at;
  int bytes = 0;
  final Map<String, MangaDlChapter> chapters;

  Map<String, Object?> toJson() => {
    'title': title,
    'cover': cover,
    'total': total,
    'at': at,
    'bytes': bytes,
    'chs': {for (final e in chapters.entries) e.key: e.value.toJson()},
  };

  static MangaDlBook? fromJson(String dir, Object? raw) {
    if (raw is! Map || dir.isEmpty) return null;
    final chs = <String, MangaDlChapter>{};
    final rawChs = raw['chs'];
    if (rawChs is Map) {
      rawChs.forEach((k, v) {
        final c = MangaDlChapter.fromJson(v);
        if (c != null) chs['$k'] = c;
      });
    }
    final b = MangaDlBook(
      dir: dir,
      title: '${raw['title'] ?? ''}',
      cover: '${raw['cover'] ?? ''}',
      total: (raw['total'] as num?)?.toInt() ?? 0,
      at: (raw['at'] as num?)?.toInt() ?? 0,
      chapters: chs,
    );
    b.bytes = (raw['bytes'] as num?)?.toInt() ??
        chs.values.fold<int>(0, (a, c) => a + c.bytes);
    return b;
  }
}
