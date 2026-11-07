import 'package:flutter/widgets.dart';

import '../utils.dart';

/// 全站共用的一个整分钟节拍。
///
/// 「刚刚 / 3 分钟前」这种东西是算出来的，页面不重画就永远停在打开那一刻。
/// 这里不各页挂定时器，统一由外壳每分钟敲一下，挂了 [LiveTime] 的那几行字
/// 自己跟着重算；没挂的界面一点都不动。
final ValueNotifier<int> clockBeat = ValueNotifier<int>(0);

/// 一分钟推到下一格。外壳（首页）负责调，其它页面别自己起定时器。
void beatClock() => clockBeat.value++;

/// 会自己更新的相对时间：刚刚 / 3 分钟前 / 昨天。
class LiveTime extends StatelessWidget {
  const LiveTime(
    this.at, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
  });

  final int at;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: clockBeat,
      builder: (context, _, _) => Text(
        timeAgo(at),
        style: style,
        maxLines: maxLines,
        overflow: overflow,
        textAlign: textAlign,
      ),
    );
  }
}

/// 时间夹在一串文字里（「@某人 · 3 分钟前 · 已编辑」）时用这个。
class LiveTimeText extends StatelessWidget {
  const LiveTimeText(
    this.text, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
  });

  final String Function() text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: clockBeat,
      builder: (context, _, _) => Text(
        text(),
        style: style,
        maxLines: maxLines,
        overflow: overflow,
        textAlign: textAlign,
      ),
    );
  }
}
