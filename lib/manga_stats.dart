import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'store.dart' show MangaPref;

/// 一本书的累计：翻了多少页、开了多少话、看了多久。
class MangaBookStat {
  String title;
  int pages;
  int chapters;
  int sec;
  int at;

  MangaBookStat({
    required this.title,
    this.pages = 0,
    this.chapters = 0,
    this.sec = 0,
    this.at = 0,
  });

  Map<String, dynamic> toJson() => {
    'n': title,
    'p': pages,
    'c': chapters,
    's': sec,
    't': at,
  };

  static MangaBookStat? fromJson(String dir, dynamic j) {
    if (j is! Map) return null;
    return MangaBookStat(
      title: (j['n'] as String?) ?? dir,
      pages: (j['p'] as num?)?.toInt() ?? 0,
      chapters: (j['c'] as num?)?.toInt() ?? 0,
      sec: (j['s'] as num?)?.toInt() ?? 0,
      at: (j['t'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 阅读统计的整份数据。
class MangaStatsData {
  int sec;
  int pages;
  int chapters;

  /// `2026-11-17` → 当天秒数。只留最近 30 天，别把盘越写越大。
  final Map<String, int> days;

  /// 书目录 → 这本书的累计。
  final Map<String, MangaBookStat> books;

  MangaStatsData({
    this.sec = 0,
    this.pages = 0,
    this.chapters = 0,
    Map<String, int>? days,
    Map<String, MangaBookStat>? books,
  }) : days = days ?? <String, int>{},
       books = books ?? <String, MangaBookStat>{};

  bool get empty => sec == 0 && pages == 0 && chapters == 0;

  /// 最常看的几本，按翻页数从多到少。
  List<MapEntry<String, MangaBookStat>> topBooks([int n = 5]) {
    final list = books.entries.toList()
      ..sort((a, b) {
        final c = b.value.pages.compareTo(a.value.pages);
        return c != 0 ? c : b.value.at.compareTo(a.value.at);
      });
    return list.take(n).toList();
  }

  /// 最近 [n] 天（含今天），老的在前。没读的那天补 0，柱状图不能缺格。
  List<(String, int)> recentDays(int n) {
    final now = DateTime.now();
    final out = <(String, int)>[];
    for (var i = n - 1; i >= 0; i--) {
      final d = now.subtract(Duration(days: i));
      final k = dayKey(d);
      out.add((k, days[k] ?? 0));
    }
    return out;
  }

  static String dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// 阅读统计的存取。
///
/// 三个写入口（时长、翻页、开话）会同时被调，都做「读-改-写」，
/// 所以串成一条队列，别让后一笔盖掉前一笔。
class MangaStats {
  static const _daysKeep = 30;
  static const _booksKeep = 50;

  static String get key => 'manga_stats_v1_${MangaPref.scope}';

  static Future<void> _queue = Future<void>.value();

  static Future<T> _serial<T>(Future<T> Function() fn) {
    final done = Completer<T>();
    _queue = _queue.then((_) async {
      try {
        done.complete(await fn());
      } catch (e, s) {
        done.completeError(e, s);
      }
    });
    return done.future;
  }

  static Future<MangaStatsData> load() => _serial(_read);

  static Future<MangaStatsData> _read() async {
    final sp = await SharedPreferences.getInstance();
    return _parse(sp.getString(key));
  }

  /// 记一段阅读时长。阅读器每分钟报一次，退出时再补零头。
  static Future<void> addSeconds(int s) {
    if (s <= 0) return Future<void>.value();
    return _serial(
      () => _mutate((d) {
        d.sec += s;
        final k = MangaStatsData.dayKey(DateTime.now());
        d.days[k] = (d.days[k] ?? 0) + s;
      }),
    );
  }

  /// 翻到一页。同一页翻两次只算一次由阅读器自己挡。
  static Future<void> addPage(String dir, String title) {
    return _serial(
      () => _mutate((d) {
        d.pages++;
        final b = d.books.putIfAbsent(dir, () => MangaBookStat(title: title));
        b.title = title;
        b.pages++;
        b.at = DateTime.now().millisecondsSinceEpoch;
      }),
    );
  }

  /// 开一话。
  static Future<void> addChapter(String dir, String title) {
    return _serial(
      () => _mutate((d) {
        d.chapters++;
        final b = d.books.putIfAbsent(dir, () => MangaBookStat(title: title));
        b.title = title;
        b.chapters++;
        b.at = DateTime.now().millisecondsSinceEpoch;
      }),
    );
  }

  static Future<void> clear() {
    return _serial(() async {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(key);
    });
  }

  static Future<void> _mutate(void Function(MangaStatsData d) fn) async {
    final sp = await SharedPreferences.getInstance();
    final d = _parse(sp.getString(key));
    fn(d);
    _trim(d);
    await sp.setString(key, jsonEncode(_dump(d)));
  }

  /// 天数按日期裁，书按最近看的时间裁。
  static void _trim(MangaStatsData d) {
    if (d.days.length > _daysKeep) {
      final keys = d.days.keys.toList()..sort();
      for (final k in keys.take(keys.length - _daysKeep)) {
        d.days.remove(k);
      }
    }
    if (d.books.length > _booksKeep) {
      final keys = d.books.keys.toList()
        ..sort((a, b) => d.books[b]!.at.compareTo(d.books[a]!.at));
      for (final k in keys.skip(_booksKeep)) {
        d.books.remove(k);
      }
    }
  }

  static MangaStatsData _parse(String? raw) {
    if (raw == null || raw.isEmpty) return MangaStatsData();
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return MangaStatsData();
      final days = <String, int>{};
      final dm = m['days'];
      if (dm is Map) {
        dm.forEach((k, v) {
          final n = (v as num?)?.toInt() ?? 0;
          if (n > 0) days['$k'] = n;
        });
      }
      final books = <String, MangaBookStat>{};
      final bm = m['books'];
      if (bm is Map) {
        bm.forEach((k, v) {
          final b = MangaBookStat.fromJson('$k', v);
          if (b != null) books['$k'] = b;
        });
      }
      return MangaStatsData(
        sec: (m['sec'] as num?)?.toInt() ?? 0,
        pages: (m['pages'] as num?)?.toInt() ?? 0,
        chapters: (m['chapters'] as num?)?.toInt() ?? 0,
        days: days,
        books: books,
      );
    } catch (_) {
      // 坏了就当没读过，下次写会盖掉。统计不值得拦人。
      return MangaStatsData();
    }
  }

  static Map<String, dynamic> _dump(MangaStatsData d) => {
    'sec': d.sec,
    'pages': d.pages,
    'chapters': d.chapters,
    'days': d.days,
    'books': {for (final e in d.books.entries) e.key: e.value.toJson()},
  };
}
