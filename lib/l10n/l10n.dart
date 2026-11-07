import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

/// 全局取文案。
///
/// 有 context 的地方也能用，但 widget 里优先 `L.of(context)`：
/// 那个跟着 Localizations 走，不用管这里刷没刷新。
///
/// 没有 context 的地方（store、api、static 方法、工具函数）只能用这个。
/// [current] 由 MaterialApp 的 builder 在每个 locale 变化时刷新，
/// 刷新点只有一处，别在别处赋值。
class Lc {
  Lc._();

  static L _current = lookupL(const Locale('zh'));

  static L get current => _current;

  static void sync(BuildContext context) {
    final v = Localizations.of<L>(context, L);
    if (v != null) _current = v;
  }

  /// 后台 isolate 没有 Localizations，只能按存的设置手动对一次。
  static void setLocale(String code) {
    _current = lookupL(Locale(code == 'en' ? 'en' : 'zh'));
  }
}
