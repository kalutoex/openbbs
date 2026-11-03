import 'package:flutter_test/flutter_test.dart';
import 'package:shijianxian_app/utils.dart';

void main() {
  test('大数字缩写', () {
    expect(bigNum(0), '0');
    expect(bigNum(9999), '9999');
    expect(bigNum(12000), '1.2万');
    expect(bigNum(123456), '12万');
  });

  test('刚刚', () {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    expect(timeAgo(now), '刚刚');
  });

  test('分钟前', () {
    final t = DateTime.now().subtract(const Duration(minutes: 5));
    expect(timeAgo(t.millisecondsSinceEpoch ~/ 1000), '5 分钟前');
  });

  test('去年给完整日期', () {
    final t = DateTime.now().subtract(const Duration(days: 400));
    final s = timeAgo(t.millisecondsSinceEpoch ~/ 1000);
    expect(s.contains('-'), isTrue);
    expect(s.split('-').length, 3);
  });
}
