import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'l10n/l10n.dart';
import 'notify.dart';
import 'pages/notice_page.dart' show noticeActionText;
import 'token_store.dart';

/// 后台那一份轮询。
///
/// 前台那条 [Poller] 靠 Dart 定时器，进程一被系统冻住就停摆，锁屏十分钟
/// 也等不来一条提醒。这里用 WorkManager 让系统自己把进程叫起来——
/// 代价是最短 15 分钟一次，慢，但它是唯一不挂常驻通知栏还能醒过来的路。
///
/// 写游标用的是和前台同一组 key（`notify_cursor_dm_u<uid>`）。前台在
/// 切回前台时会 `reload()` 再读一遍，两边不会各自弹一次。
const bgTaskUnique = 'openbbs-notify-poll';
const bgTaskName = 'notifyPoll';

const _kCtx = 'bg_ctx';

/// 后台这轮跑到哪、死在哪。前台自检里会读出来显示——
/// 后台 isolate 的异常没人看得见，不落盘就只能干猜。
const _kDiag = 'bg_diag';
const _kRuns = 'bg_runs';
const _kDm = 'notify_cursor_dm';
const _kNt = 'notify_cursor_nt';

@pragma('vm:entry-point')
void bgCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    unawaited(BgPoll.countRun());
    try {
      await BgPoll.run();
    } catch (e) {
      debugPrint('bgPoll: $e');
      await BgPoll.diag('炸了: $e');
    }
    // 永远回 true：失败也等下一轮，别让系统按退避把间隔越拉越长。
    return true;
  });
}

class BgPoll {
  BgPoll._();

  /// 系统叫起来一次记一次，顺便把时间写上。
  static Future<void> countRun() async {
    try {
      final p = await SharedPreferences.getInstance();
      final n = (p.getInt(_kRuns) ?? 0) + 1;
      await p.setInt(_kRuns, n);
      await p.setString(
        _kDiag,
        '${DateTime.now().millisecondsSinceEpoch}|第 $n 次唤醒',
      );
    } catch (_) {}
  }

  /// 记一行「跑到哪了」，前台自检读取。
  static Future<void> diag(String msg) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
        _kDiag,
        '${DateTime.now().millisecondsSinceEpoch}|$msg',
      );
    } catch (_) {}
  }

  /// 自检用：上次后台跑的时间和结果。
  static Future<List<String>> diagLines() async {
    try {
      final p = await SharedPreferences.getInstance();
      final n = p.getInt(_kRuns) ?? 0;
      final raw = p.getString(_kDiag) ?? '';
      final i = raw.indexOf('|');
      var when = '从没跑过';
      if (i > 0) {
        final ms = int.tryParse(raw.substring(0, i)) ?? 0;
        if (ms > 0) {
          final d = DateTime.fromMillisecondsSinceEpoch(ms);
          when =
              '${d.month}-${d.day} '
              '${d.hour.toString().padLeft(2, '0')}:'
              '${d.minute.toString().padLeft(2, '0')}:'
              '${d.second.toString().padLeft(2, '0')}';
        }
      }
      return [
        '后台: 累计唤醒 $n 次，最近 $when',
        '后台最后一步: ${i > 0 ? raw.substring(i + 1) : '无'}',
      ];
    } catch (_) {
      return const ['后台: 读不到记录'];
    }
  }

  /// 前台记下来的上下文：当前站的入口和账号。
  ///
  /// 后台 isolate 里没有 AppState，站点表、登录态都读不到，
  /// 只能靠前台定期把这两样写进 prefs。
  static Future<void> syncContext({
    required String base,
    required List<String> endpoints,
    required int uid,
  }) async {
    if (base.isEmpty || uid <= 0) return;
    final p = await SharedPreferences.getInstance();
    final raw = jsonEncode({
      'base': base,
      'alts': endpoints.where((e) => e.isNotEmpty).take(4).toList(),
      'uid': uid,
    });
    if (p.getString(_kCtx) == raw) return;
    await p.setString(_kCtx, raw);
  }

  /// 跑一次。游标怎么推进跟前台一模一样，别看岔了。
  static Future<void> run() async {
    if (kIsWeb || !Platform.isAndroid) return;
    // 后台 isolate 里插件默认没注册，shared_preferences 会直接炸。
    DartPluginRegistrant.ensureInitialized();

    final p = await SharedPreferences.getInstance();
    if (!(p.getBool('sys_notify') ?? true)) {
      await diag('系统通知开关是关的，跳过');
      return;
    }

    final raw = p.getString(_kCtx);
    if (raw == null || raw.isEmpty) {
      await diag('没有站点上下文（前台还没同步过）');
      return;
    }
    Map ctx;
    try {
      ctx = jsonDecode(raw) as Map;
    } catch (_) {
      return;
    }
    final uid = (ctx['uid'] as num?)?.toInt() ?? 0;
    final base = '${ctx['base'] ?? ''}';
    if (uid <= 0 || base.isEmpty) {
      await diag('上下文不完整 uid=$uid base=$base');
      return;
    }

    final token = await TokenStore.read();
    if (token == null || token.isEmpty) {
      await diag('读不到登录令牌');
      return;
    }

    // 文案跟着设置走，不然英文界面下弹一条中文。
    final lc = p.getString('locale') ?? '';
    if (lc == 'en' || lc == 'zh') Lc.setLocale(lc);

    final dmKey = _cursorKey(_kDm, uid);
    final ntKey = _cursorKey(_kNt, uid);
    final dm0 = p.getInt(dmKey) ?? p.getInt(_kDm) ?? 0;
    final nt0 = p.getInt(ntKey) ?? p.getInt(_kNt) ?? 0;

    final m = await _poll(ctx, base, token, dm0, nt0);
    if (m == null) {
      await diag('请求失败: 入口全不通');
      return;
    }

    final dm = (m['dm'] as Map).cast<String, dynamic>();
    final nt = (m['notice'] as Map).cast<String, dynamic>();

    await _handleDm(p, dmKey, dm0, dm);
    await _handleNotice(p, ntKey, nt0, nt);

    await diag('跑完: 私信未读 ${dm['total'] ?? 0} 条，站内 ${nt['total'] ?? 0} 条');
  }

  static String _cursorKey(String base, int uid) => '${base}_u$uid';

  /// 一个入口不通就换下一个。全挂了就当这轮没发生过，游标不动。
  static Future<Map?> _poll(
    Map ctx,
    String base,
    String token,
    int dmSince,
    int ntSince,
  ) async {
    final urls = <String>[base];
    for (final e in (ctx['alts'] as List?) ?? const []) {
      final s = '$e';
      if (s.isNotEmpty && !urls.contains(s)) urls.add(s);
    }
    for (final b in urls) {
      try {
        final u =
            Uri.parse(
              '${b.endsWith('/') ? b.substring(0, b.length - 1) : b}/api/notify/poll',
            ).replace(
              queryParameters: {'dm_since': '$dmSince', 'nt_since': '$ntSince'},
            );
        final r = await http
            .get(u, headers: {'Authorization': 'Bearer $token'})
            .timeout(const Duration(seconds: 20));
        if (r.statusCode >= 400) continue;
        final body = jsonDecode(utf8.decode(r.bodyBytes));
        if (body is Map && body['dm'] is Map && body['notice'] is Map) {
          return body;
        }
      } catch (_) {
        // 这个入口不行，试下一个
      }
    }
    return null;
  }

  static Future<void> _handleDm(
    SharedPreferences p,
    String key,
    int since,
    Map<String, dynamic> dm,
  ) async {
    final last = (dm['last_id'] as num?)?.toInt() ?? 0;
    final items = ((dm['items'] as List?) ?? const []).cast<Map>();

    // 第一次跑：只记游标，别一装上就弹一屏历史。
    if (since == 0) {
      if (last > 0) await p.setInt(key, last);
      return;
    }

    if (items.isEmpty) {
      if (last > since) await p.setInt(key, last);
      return;
    }

    final fresh = [
      for (final e in items)
        if (((e['id'] as num?)?.toInt() ?? 0) > since) e,
    ];

    final newest = (items.last['id'] as num?)?.toInt() ?? last;
    final next = newest > last ? newest : last;
    if (next > since) await p.setInt(key, next);

    if (fresh.isEmpty) return;
    await SysNotify.init((_) {});

    // 同一个人的连发合成一条，不同的人各占一条。
    final byPeer = <int, List<Map>>{};
    for (final e in fresh) {
      final peer = (e['peer_id'] as num?)?.toInt() ?? 0;
      byPeer.putIfAbsent(peer, () => []).add(e);
    }
    final errs = <String>[];
    for (final entry in byPeer.entries) {
      final list = entry.value;
      final lastOne = list.last;
      final who = '${lastOne['peer_name'] ?? ''}';
      final err = await SysNotify.show(
        id: 10000 + (entry.key % 1000),
        title: list.length == 1 ? who : Lc.current.notifyNewCount(list.length),
        body: list.length == 1
            ? _bubbleText(lastOne)
            : '$who：${_bubbleText(lastOne)}',
        payload: 'dm:${entry.key}:$who',
      );
      if (err != null) errs.add(err);
    }
    await diag(
      errs.isEmpty ? '私信弹了 ${byPeer.length} 条' : '私信弹失败: ${errs.join(' / ')}',
    );
  }

  static Future<void> _handleNotice(
    SharedPreferences p,
    String key,
    int since,
    Map<String, dynamic> nt,
  ) async {
    final last = (nt['last_id'] as num?)?.toInt() ?? 0;
    final items = ((nt['items'] as List?) ?? const []).cast<Map>();

    if (since == 0) {
      if (last > 0) await p.setInt(key, last);
      return;
    }

    if (items.isEmpty) {
      if (last > since) await p.setInt(key, last);
      return;
    }

    final fresh = [
      for (final e in items)
        if (((e['id'] as num?)?.toInt() ?? 0) > since) e,
    ];

    final newest = (items.last['id'] as num?)?.toInt() ?? last;
    final next = newest > last ? newest : last;
    if (next > since) await p.setInt(key, next);

    if (fresh.isEmpty) return;
    await SysNotify.init((_) {});

    final e = fresh.last;
    final who = '${e['actor'] ?? ''}';
    await SysNotify.show(
      id: SysNotify.idNotice,
      title: fresh.length == 1 ? who : Lc.current.notifyNewCount(fresh.length),
      body: fresh.length == 1
          ? noticeActionText('${e['kind'] ?? ''}')
          : '$who ${noticeActionText('${e['kind'] ?? ''}')}',
      payload: 'notice',
    );
  }

  /// 纯图片的消息没字，得给个说法。
  static String _bubbleText(Map e) {
    final body = '${e['body'] ?? ''}'.trim();
    if (body.isNotEmpty) return body;
    return (e['image'] as bool? ?? false)
        ? Lc.current.replyImage
        : Lc.current.notifyNewDm;
  }
}
