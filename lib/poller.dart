import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'bg_poll.dart';
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

  /// 游标按账号分开存。id 体系全站一套，但「我处理到哪」是按人算的：
  /// 拿上个号的进度去卡新号，要么一条不弹，要么一口气弹一堆旧的。
  String _cursorKey(String base) => _uid == 0 ? base : '${base}_u$_uid';

  /// 前台这么快，是为了让「对方刚发完」到「我这边弹出来」之间几乎无感。
  static const _fgSeconds = 5;
  static const _bgSeconds = 60;

  Timer? _t;
  bool _busy = false;
  bool _on = false;
  bool _fore = true;
  int _fails = 0;
  int _lastLog = 0;

  /// 游标：这两条之前的消息都处理过（弹过或不值得弹）。
  int _dm = 0;
  int _nt = 0;

  /// 这份游标属于谁。登录态一变就得换一份。
  int _uid = 0;

  /// 上次交给后台任务的那份上下文，用来判断要不要重写。
  String _ctxBase = '';
  int _ctxUid = -1;

  /// 正开着的会话，这个人的消息不弹——人就在看着。
  int activePeer = 0;

  SharedPreferences? _p;

  Future<void> start() async {
    if (_on) return;
    _on = true;
    _p = await SharedPreferences.getInstance();
    _uid = AppState.instance.uid;
    _loadCursors();
    // 登录态一变（登入、切号、退出）就换游标。挂在状态上比在各处埋调用
    // 可靠——现在有三条路径能换账号，漏一条就是静默不弹通知。
    AppState.instance.addListener(_onState);
    WidgetsBinding.instance.addObserver(this);
    _fore = true;
    _arm();
    unawaited(tick());
  }

  /// 把当前账号的游标读进内存。
  void _loadCursors() {
    final p = _p;
    if (p == null) return;
    if (_uid == 0) {
      // 没登录的时候还停在旧版那份不带账号的 key 上，别去动它。
      _dm = p.getInt(_kDm) ?? 0;
      _nt = p.getInt(_kNt) ?? 0;
      return;
    }
    _dm = p.getInt(_cursorKey(_kDm)) ?? _adopt(_kDm);
    _nt = p.getInt(_cursorKey(_kNt)) ?? _adopt(_kNt);
  }

  /// 老版本的游标不带账号。第一次按 uid 读不到时继承过来，然后当场删掉，
  /// 免得第二个登录的账号也捡到同一份。
  int _adopt(String base) {
    final p = _p;
    if (p == null) return 0;
    final v = p.getInt(base) ?? 0;
    if (v > 0) {
      unawaited(p.setInt(_cursorKey(base), v));
      unawaited(p.remove(base));
    }
    return v;
  }

  /// 换号了：换成新账号自己那份游标。
  ///
  /// 之前没接上这里，切完号 `_dm/_nt` 还是上一个人的位置。新号的消息 id
  /// 比它小就一直「没有新消息」，通知一条不弹，角标却是准的，特别难查。
  Future<void> onAccountChanged() async {
    _p ??= await SharedPreferences.getInstance();
    final uid = AppState.instance.uid;
    if (uid == _uid) return;
    _uid = uid;
    _dm = 0;
    _nt = 0;
    _loadCursors();
  }

  void _onState() {
    if (AppState.instance.uid != _uid) unawaited(onAccountChanged());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final fg = state == AppLifecycleState.resumed;
    if (fg == _fore) return;
    _fore = fg;
    _arm();
    // 切回来先重读一遍游标：后台那份可能已经在别的 isolate 里推进过了，
    // 内存里这个数还是旧的，会把它刚弹过的消息再弹一次。
    if (fg) unawaited(_refreshThenTick());
  }

  Future<void> _refreshThenTick() async {
    try {
      if (AppState.instance.uid != _uid) {
        await onAccountChanged();
      } else {
        await _p?.reload();
        _loadCursors();
      }
    } catch (_) {
      // 读不出来就按旧游标走，顶多多弹一条
    }
    await tick();
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
      // 顺手把「当前在哪座站、哪个号」留给后台任务，它那边读不到 AppState。
      await _syncBgContext();
    } catch (e) {
      _fails++;
      // 以前这里全吞掉。服务端把 dm 改成数组，这里就每天静默失败一万多次，
      // 角标不动、通知不弹，控制台一个字都没有。限流打一行，够查就行。
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastLog > 60000) {
        _lastLog = now;
        debugPrint('poller: 第 $_fails 次失败: $e');
      }
    } finally {
      _busy = false;
      _arm();
    }
  }

  /// 每次成功后对一遍。内容没变就不写盘，省得每 5 秒动一次闪存。
  Future<void> _syncBgContext() async {
    final st = AppState.instance;
    if (!st.loggedIn || Api.base.isEmpty) return;
    if (Api.base == _ctxBase && st.uid == _ctxUid) return;
    _ctxBase = Api.base;
    _ctxUid = st.uid;
    await BgPoll.syncContext(
      base: Api.base,
      endpoints: Api.endpoints,
      uid: st.uid,
    );
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
    await _p?.setInt(_cursorKey(k), v);
  }

  /// 退出登录时清掉这个账号的游标。
  Future<void> reset() async {
    _dm = 0;
    _nt = 0;
    await _p?.remove(_cursorKey(_kDm));
    await _p?.remove(_cursorKey(_kNt));
    await SysNotify.cancel(SysNotify.idDm);
    await SysNotify.cancel(SysNotify.idNotice);
  }
}
