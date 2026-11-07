import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'app_globals.dart';
import 'cloud.dart';
import 'file_pick.dart';
import 'l10n/l10n.dart';
import 'upload_keepalive.dart';

enum UploadState { queued, running, done, failed }

/// 一包正在传的东西。云盘页只是订阅它，页面关掉也照样传。
class UploadJob {
  UploadJob({required this.file});

  final PickedFile file;
  String get name => file.name;
  int get size => file.size;

  UploadState state = UploadState.queued;
  int got = 0;
  double speed = 0;
  String error = '';

  DateTime _tick = DateTime.now();
  int _tickBytes = 0;

  bool get active =>
      state == UploadState.queued || state == UploadState.running;

  double get ratio =>
      size > 0 ? (got / size).clamp(0.0, 1.0) : (state == UploadState.done ? 1 : 0);
}

/// 上传队列，全 App 一份。
///
/// 放在这里而不是页面 State 里，是因为一个 1GB 的包要传十几分钟，
/// 这中间人总要干点别的——退出云盘页、去看消息、甚至退到桌面。
/// 任务挂在页面上，页面一没就跟着没了；挂在这里，谁都关不掉它。
class UploadManager extends ChangeNotifier {
  UploadManager._();

  static final UploadManager i = UploadManager._();

  final List<UploadJob> jobs = [];

  /// 累计传完几个。页面靠它判断要不要刷新列表——它自己可能中途才回来。
  int doneCount = 0;
  int failedCount = 0;

  /// 串行跑。同时开几条上传，慢网下只会互相抢带宽，反而都慢。
  Future<void> _chain = Future<void>.value();

  UploadJob? get current {
    for (final j in jobs) {
      if (j.state == UploadState.running) return j;
    }
    for (final j in jobs) {
      if (j.state == UploadState.queued) return j;
    }
    return null;
  }

  bool get busy => current != null;

  int get queuedAfter =>
      jobs.where((j) => j.state == UploadState.queued).length;

  void add(PickedFile f) {
    final job = UploadJob(file: f);
    jobs.add(job);
    _trim();
    notifyListeners();
    _chain = _chain.then((_) => _run(job));
  }

  void addAll(Iterable<PickedFile> fs) {
    for (final f in fs) {
      add(f);
    }
  }

  Future<void> _run(UploadJob job) async {
    job.state = UploadState.running;
    job.got = 0;
    job.speed = 0;
    job._tick = DateTime.now();
    job._tickBytes = 0;
    // 安卓那边挂个前台服务：切出去回消息、锁屏，进程也不会被冻住。
    unawaited(keepAliveStart(_label(job), '0%'));
    notifyListeners();
    try {
      await Api.uploadFile(job.file, onProgress: (got, total) {
        final now = DateTime.now();
        final dt = now.difference(job._tick).inMilliseconds;
        // 上万次回调全量刷新没意义，又没有动画可看。
        if (got < total && dt < 120) return;
        final delta = got - job._tickBytes;
        job._tick = now;
        job._tickBytes = got;
        job.got = got;
        if (dt > 0) job.speed = delta * 1000 / dt;
        _notifyBar(job);
        notifyListeners();
      });
      job.state = UploadState.done;
      job.got = job.size;
      doneCount++;
      _finishBar();
      _say(Lc.current.uploadedDone);
    } catch (e) {
      job.state = UploadState.failed;
      job.error = _msg(e);
      failedCount++;
      _finishBar();
      _say(job.error);
    }
    notifyListeners();
  }

  String _label(UploadJob job) => job.size > 0
      ? '${job.name} · ${bytesText(job.size)}'
      : job.name;

  /// 通知栏的刷新别跟着 120ms 走，太密。两秒一次足够看出在动。
  DateTime _barTick = DateTime.fromMillisecondsSinceEpoch(0);

  void _notifyBar(UploadJob job) {
    final now = DateTime.now();
    if (now.difference(_barTick).inMilliseconds < 2000) return;
    _barTick = now;
    final pct = (job.ratio * 100).round();
    unawaited(keepAliveUpdate(_label(job), '$pct%${_speedText(job)}'));
  }

  String _speedText(UploadJob job) =>
      job.speed > 0 ? ' · ${bytesText(job.speed.round())}/s' : '';

  /// 队列里还有就继续挂着，传干净了才把通知撤掉。
  void _finishBar() {
    if (current == null) unawaited(keepAliveStop());
  }

  String _msg(Object e) {
    if (e is ApiException) return e.message;
    final s = e.toString();
    return s.startsWith('Exception: ') ? s.substring(11) : s;
  }

  /// 页面可能早就没了，提示只能走全局。
  void _say(String text) {
    final m = appMessenger.currentState;
    if (m == null) return;
    m
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          duration: const Duration(milliseconds: 1500),
        ),
      );
  }

  /// 只留最近几条，传完的别一直堆着。队列里的和正在传的不动。
  void _trim() {
    const keep = 20;
    while (jobs.length > keep && jobs.first.state != UploadState.running) {
      if (jobs.first.active) break;
      jobs.removeAt(0);
    }
  }

  /// 把已经了结的清掉。失败的那条留给人看一眼再清。
  void clearFinished() {
    jobs.removeWhere((j) => j.state == UploadState.done);
    notifyListeners();
  }
}
