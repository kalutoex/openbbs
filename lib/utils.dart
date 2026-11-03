import 'l10n/l10n.dart';

/// 贴吧那种「刚刚 / 3 分钟前 / 昨天 12:30 / 2025-08-01」的时间写法。
String timeAgo(int ts) {
  final l = Lc.current;
  final t = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
  final now = DateTime.now();
  final diff = now.difference(t);
  if (diff.inSeconds < 60) return l.justNow;
  if (diff.inMinutes < 60) return l.minutesAgo('${diff.inMinutes}');
  if (diff.inHours < 24 && now.day == t.day) {
    return '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
  }
  final y = now.subtract(const Duration(days: 1));
  if (y.year == t.year && y.month == t.month && y.day == t.day) {
    return l.yesterday;
  }
  if (now.year == t.year) {
    return '${t.month.toString().padLeft(2, '0')}-'
        '${t.day.toString().padLeft(2, '0')}';
  }
  return '${t.year}-${t.month.toString().padLeft(2, '0')}-'
      '${t.day.toString().padLeft(2, '0')}';
}

/// 大数字：1.2 万 / 10 万，英文那边是 12k / 100k
String bigNum(int n) {
  if (n < 10000) return '$n';
  final w = n / 10000;
  return w >= 10
      ? Lc.current.bigNumSuffix('${w.toStringAsFixed(0)}')
      : Lc.current.bigNumSuffix('${w.toStringAsFixed(1)}');
}

/// 帖子详情里的时间写法：26年10月16日, 4:43 下午
String postTime(int ts) {
  final t = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final l = Lc.current;
  return l.postTimeFmt(
    '${t.year % 100}',
    '${t.month}',
    '${t.day}',
    '$h',
    t.minute.toString().padLeft(2, '0'),
    t.hour < 12 ? l.am : l.pm,
  );
}
