import 'dart:async';

import 'package:flutter/material.dart';

import '../manga_stats.dart';

/// 阅读统计。
///
/// 数据全在本地（按站 + 人分开存），不发服务端——看的什么书是私事。
/// 这里只读不写，唯一能改的是右上角那个「清空」。
class MangaStatsPage extends StatefulWidget {
  const MangaStatsPage({super.key});

  @override
  State<MangaStatsPage> createState() => _MangaStatsPageState();
}

class _MangaStatsPageState extends State<MangaStatsPage> {
  MangaStatsData? _d;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final d = await MangaStats.load();
    if (!mounted) return;
    setState(() => _d = d);
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空阅读统计？'),
        content: const Text('只删本机这份，书签和阅读位置不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await MangaStats.clear();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final d = _d;
    return Scaffold(
      appBar: AppBar(
        title: const Text('阅读统计'),
        actions: [
          IconButton(
            onPressed: (d == null || d.empty) ? null : _clear,
            icon: const Icon(Icons.delete_outline),
            tooltip: '清空',
          ),
        ],
      ),
      body: d == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Row(
                  children: [
                    _card(cs, '累计时长', _dur(d.sec), Icons.schedule),
                    const SizedBox(width: 10),
                    _card(cs, '翻过', '${d.pages} 页', Icons.auto_stories),
                    const SizedBox(width: 10),
                    _card(cs, '开过', '${d.chapters} 话', Icons.menu_book),
                  ],
                ),
                const SizedBox(height: 22),
                Text(
                  '最近 7 天',
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.outline,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                _bars(cs, d.recentDays(7)),
                const SizedBox(height: 24),
                Text(
                  '最常看',
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.outline,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                if (d.books.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    child: Text(
                      d.empty ? '还没读过什么。翻开一话就开始记了。' : '还没有明细。',
                      style: TextStyle(color: cs.outline, fontSize: 13),
                    ),
                  )
                else
                  for (final e in d.topBooks())
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        e.value.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${e.value.pages} 页 · ${e.value.chapters} 话',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: Text(
                        _dur(e.value.sec),
                        style: TextStyle(fontSize: 12, color: cs.outline),
                      ),
                    ),
              ],
            ),
    );
  }

  Widget _card(ColorScheme cs, String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: .55),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: cs.outline),
            const SizedBox(height: 8),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 11, color: cs.outline)),
          ],
        ),
      ),
    );
  }

  /// 七根柱子。没有读数的那天留一截灰底，不然看着像缺了格。
  Widget _bars(ColorScheme cs, List<(String, int)> days) {
    final max = days.fold<int>(0, (m, e) => e.$2 > m ? e.$2 : m);
    final labels = const ['一', '二', '三', '四', '五', '六', '日'];
    return SizedBox(
      height: 96,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final e in days)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    e.$2 <= 0 ? '' : _short(e.$2),
                    style: TextStyle(fontSize: 9, color: cs.outline),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    height: 4 + (max <= 0 ? 0 : 58 * (e.$2 / max)),
                    margin: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: BoxDecoration(
                      color: e.$2 <= 0
                          ? cs.outlineVariant.withValues(alpha: .5)
                          : cs.primary.withValues(alpha: .8),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    labels[_weekIdx(e.$1)],
                    style: TextStyle(fontSize: 10, color: cs.outline),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// yyyy-MM-dd → 0..6（周一起）。解析不出来就画个点。
  int _weekIdx(String key) {
    final d = DateTime.tryParse(key);
    if (d == null) return 0;
    return (d.weekday - 1).clamp(0, 6);
  }

  static String _short(int sec) {
    final m = sec ~/ 60;
    if (m >= 60) return '${(m / 60).toStringAsFixed(1)}h';
    return '${m}m';
  }

  static String _dur(int sec) {
    if (sec < 60) return '不到 1 分';
    final m = sec ~/ 60;
    if (m < 60) return '$m 分';
    final h = m ~/ 60;
    final r = m % 60;
    return r == 0 ? '$h 小时' : '$h 小时 $r 分';
  }
}
