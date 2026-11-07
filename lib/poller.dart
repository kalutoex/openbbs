import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'l10n/l10n.dart';
import 'notify.dart';
import 'pages/notice_page.dart' show noticeActionText;
import 'store.dart';

/// 全站唯一的消息轮询。
///
/// 以前散在两处：首页 60 秒拉一次未读数，私信页 15 秒拉一次消息，各拉各的。
/// 现在合成一个循环：前台 5 秒、后台 60 秒，一次请求把私信和站内消息都带回来，
/// 顺手更新底部角标。
///
/// 后台能不能真的跑起来取决于系统给不给活路——被冻住时定时器就停了，
/// 等切回前台会立刻补一次。这点没法靠代码解决。
class Poller with WidgetsBindingObserver {
  Poller._();
  static final Poller instance = Poller._();

  static const _kDm = 'notify_cursor_dm';
  static const _kNt = 'notify_cursor_nt';

  /// 前台这么快，是为了让「对方刚发完」到「我这边弹出来」之间几乎无感。
  static const _fgSeconds = 5;
  static const _bgSeconds = 60;

  Timer? _t;
  bool _busy = false;
  bool _on = false;
  bool _fore = true;
  int _fails = 0;

  /// 游标：这两条之前的消息都处理过（弹过或不值得弹）。
  int _dm = 0;
  int _nt = 0;

  /// 正开着的会话，这个人的消息不弹——人就在看着。
  int activePeer = 0;

  SharedPreferences? _p;

  Future<void> start() async {
    if (_on) return;
    _on = true;
    _p = await SharedPreferences.getInstance();
    _dm = _p!.getInt(_kDm) ?? 0;
    _nt = _p!.getInt(_kNt) ?? 0;
    WidgetsBinding.instance.addObserver(this);
    _fore = true;
    _arm();
    unawaited(tick());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final fg = state == AppLifecycleState.resumed;
    if (fg == _fore) return;
    _fore = fg;
    _arm();
    // 切回来马上补一次，别让人盯着旧角标等 5 秒。
    if (fg) unawaited(tick());
  }

  void _arm() {
    _t?.cancel();
    if (!_on) return;
    var secs = _fore ? _fgSeconds : _bgSeconds;
    // 连着失败就别按 5 秒死磕，断了网还每 5 秒捅一次很费电。
    if (_fails >= 3 && secs < 30) secs = 30;
    _t = Timer(Duration(seconds: secs), () => unawaited(tick()));
  }

  Future<void> tick() async {
    if (!_on) return;
    if (_busy) return;
    final st = AppState.instance;
    if (!st.loggedIn || !st.autoUnread.value) {
      _arm();
      return;
    }
    _busy = true;
    try {
      final d = await Api.get(
        '/notify/poll',
        query: {'dm_since': '$_dm', 'nt_since': '$_nt'},
      );
      final m = d as Map;
      final dm = (m['dm'] as Map).cast<String, dynamic>();
      final nt = (m['notice'] as Map).cast<String, dynamic>();
      _fails = 0;

      st.setBadges(
        dm: dm['total'] as int? ?? 0,
        notice: nt['total'] as int? ?? 0,
      );

      await _handleDm(dm);
      await _handleNotice(nt);
    } catch (_) {
      _fails++;
    } finally {
      _busy = false;
      _arm();
    }
  }

  Future<void> _handleDm(Map<String, dynamic> dm) async {
    final last = dm['last_id'] as int? ?? 0;
    final items = (dm['items'] as List?) ?? const [];

    // 第一次跑：只记游标。否则一装上就弹一屏历史消息。
    if (_dm == 0) {
      if (last > 0) await _save(_kDm, last);
      _dm = last;
      return;
    }

    if (items.isEmpty) {
      if (last > _dm) await _save(_kDm, last);
      if (last > _dm) _dm = last;
      return;
    }

    final fresh = <Map>[
      for (final e in items)
        if (((e as Map)['id'] as int? ?? 0) > _dm &&
            (e['peer_id'] as int? ?? 0) != activePeer)
          e,
    ];

    // 游标推到拿到的最后一条，不管弹不弹——弹过的、正在看的都算处理过。
    final newest = (items.last as Map)['id'] as int? ?? last;
    final next = newest > last ? newest : last;
    if (next > _dm) {
      await _save(_kDm, next);
      _dm = next;
    }

    if (fresh.isEmpty || !AppState.instance.sysNotify.value) return;

    // 按会话分组：同一个人的连发合成一条，换着看它就行；
    // 不同的人各占一条，不会互相盖掉。
    final byPeer = <int, List<Map>>{};
    for (final e in fresh) {
      final p = (e)['peer_id'] as int? ?? 0;
      byPeer.putIfAbsent(p, () => []).add(e);
    }
    for (final entry in byPeer.entries) {
      final list = entry.value;
      final lastOne = list.last;
      final who = (lastOne['peer_name'] as String?) ?? '';
      await SysNotify.show(
        // 条数从 1 涨到 n 也是同一条，别在通知栏里越堆越多
        id: _dmNotifyId(entry.key),
        title: list.length == 1 ? who : Lc.current.notifyNewCount(list.length),
        body: list.length == 1
            ? _bubbleText(lastOne)
            : '$who：${_bubbleText(lastOne)}',
        payload: 'dm:${entry.key}:$who',
      );
    }
  }

  /// 每个会话一个通知 id。1001 起往上排，跟站内通知那条(1002)错开。
  int _dmNotifyId(int peer) => 10000 + (peer % 1000);

  Future<void> _handleNotice(Map<String, dynamic> nt) async {
    final last = nt['last_id'] as int? ?? 0;
    final items = (nt['items'] as List?) ?? const [];

    if (_nt == 0) {
      if (last > 0) await _save(_kNt, last);
      _nt = last;
      return;
    }

    if (items.isEmpty) {
      if (last > _nt) await _save(_kNt, last);
      if (last > _nt) _nt = last;
      return;
    }

    final fresh = [
      for (final e in items)
        if (((e as Map)['id'] as int? ?? 0) > _nt) e,
    ];

    final newest = (items.last as Map)['id'] as int? ?? last;
    final next = newest > last ? newest : last;
    if (next > _nt) {
      await _save(_kNt, next);
      _nt = next;
    }

    if (fresh.isEmpty || !AppState.instance.sysNotify.value) return;

    if (fresh.length == 1) {
      final e = fresh.first;
      final who = (e['actor'] as String?) ?? '';
      await SysNotify.show(
        id: SysNotify.idNotice,
        title: who,
        body: noticeActionText((e['kind'] as String?) ?? ''),
        payload: 'notice',
      );
      return;
    }

    final e = fresh.last;
    final who = (e['actor'] as String?) ?? '';
    await SysNotify.show(
      id: SysNotify.idNotice,
      title: Lc.current.notifyNewCount(fresh.length),
      body: '$who ${noticeActionText((e['kind'] as String?) ?? '')}',
      payload: 'notice',
    );
  }

  /// 私信正文：纯图片的消息没字，得给个说法。
  String _bubbleText(Map e) {
    final body = (e['body'] as String?) ?? '';
    if (body.trim().isNotEmpty) return body.trim();
    return (e['image'] as bool? ?? false)
        ? Lc.current.replyImage
        : Lc.current.notifyNewDm;
  }

  Future<void> _save(String k, int v) async {
    await _p?.setInt(k, v);
  }

  /// 退出登录时清游标：换号之后 id 体系还是同一套，但别拿旧号的位置去
  /// 卡新号的消息。
  Future<void> reset() async {
    _dm = 0;
    _nt = 0;
    await _p?.remove(_kDm);
    await _p?.remove(_kNt);
    await SysNotify.cancel(SysNotify.idDm);
    await SysNotify.cancel(SysNotify.idNotice);
  }
}
