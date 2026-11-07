import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

/// 界面参数：卡片高度、边距、字号这类纯视觉的数字，值由服务端下发。
///
/// 站长在管理页改一次，客户端下次拉取就换过来，不用重新打安装包。
/// 拉不到、值不对、服务端还是老版本没这个接口——一律退回 [defaults]。
/// 界面宁可长得旧，也不能因为这些数字画不出来。
class UiConfig {
  UiConfig._();

  static const _kCache = 'ui_spec_cache';

  /// 出厂长相。服务端一个键都没配时，界面就是这个样子。
  ///
  /// 服务端只发它改过的键，剩下的靠这里补，所以加新键不用等后台升级。
  static const Map<String, dynamic> defaults = {
    // 附件卡片。主页、帖子内、私信三处共用一套。
    'fileCard.height': 80,
    // 主页/列表里的紧凑附件卡：没有底板，比详情页的大卡矮一截。
    'fileCard.compactHeight': 56,
    'fileCard.maxWidth': 420,
    // 私信的气泡比整页窄，卡片跟着收一点，别横着撑破气泡。
    'fileCard.compactWidth': 240,
    'fileCard.padV': 2,
    'fileCard.padH': 8,
    'fileCard.radius': 10,
    'fileCard.icon': 40,
    'fileCard.nameSize': 16,
    'fileCard.sizeSize': 12.5,
    'fileCard.gap': 10,
    'fileCard.arrowIcon': 15,
    // 帖子列表卡片。
    'threadCard.avatarRadius': 20,
    'threadCard.gap': 12,
    // 角标相对时间的位置：leftOfTime / rightOfTime / belowTime
    'threadCard.tagSide': 'leftOfTime',
  };

  static Map<String, dynamic> _values = Map.of(defaults);

  /// 服务端那份配置的版本号，只用来排查「到底生效了没有」。
  static int rev = 0;

  /// 数字参数。取不到、类型不对都退回默认值。
  static double px(String key) {
    final v = _values[key];
    if (v is num) return v.toDouble();
    if (v is String) {
      final d = double.tryParse(v);
      if (d != null) return d;
    }
    final d = defaults[key];
    return d is num ? d.toDouble() : 0;
  }

  static String str(String key) {
    final v = _values[key];
    if (v is String) return v;
    final d = defaults[key];
    return d is String ? d : '';
  }

  /// 先把上次的缓存贴上来（断网也画得对），再去服务端要新的。
  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_kCache);
      if (raw != null) _apply(jsonDecode(raw));
    } catch (_) {
      // 缓存坏了不影响继续拉
    }
    try {
      final d = await Api.get('/ui/config');
      _apply(d);
      final p = await SharedPreferences.getInstance();
      await p.setString(_kCache, jsonEncode(d));
    } catch (_) {
      // 老服务端没这个接口，或者这会儿断网：用缓存/默认值
    }
  }

  /// 服务端改完之后想立刻看到效果，重新拉一次就行。
  static Future<void> refresh() => load();

  static void _apply(dynamic d) {
    if (d is! Map) return;
    rev = d['rev'] is num ? (d['rev'] as num).toInt() : 0;
    final vals = d['values'];
    _values = Map.of(defaults);
    if (vals is! Map) return;
    for (final e in vals.entries) {
      final k = '${e.key}';
      // 不认识的键直接丢掉：后台可能比客户端新，多出来的字段不该影响渲染。
      if (!defaults.containsKey(k)) continue;
      _values[k] = e.value;
    }
  }
}
