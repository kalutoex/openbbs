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
      ? Lc.current.bigNumSuffix(w.toStringAsFixed(0))
      : Lc.current.bigNumSuffix(w.toStringAsFixed(1));
}

/// 容量卡片用的短写法：1.2G / 500M / 12K。
///
/// GB 保留 1 位，整数就不带小数点（5G 而不是 5.0G）。
String bytesShort(int size) {
  if (size < 0) size = 0;
  double n = size.toDouble();
  const units = ['B', 'K', 'M', 'G', 'T'];
  var i = 0;
  while (n >= 1024 && i < units.length - 1) {
    n /= 1024;
    i++;
  }
  if (i == 0) return '${n.toStringAsFixed(0)}B';
  final s = n.toStringAsFixed(1);
  return '${s.endsWith('.0') ? s.substring(0, s.length - 2) : s}${units[i]}';
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
