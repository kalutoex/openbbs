import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'app_globals.dart';
import 'file_pick.dart';
import 'l10n/l10n.dart';
import 'upload_keepalive.dart';
import 'utils.dart';

enum UploadState { queued, running, done, failed, cancelled }

/// 一包正在传的东西。云盘页只是订阅它，页面关掉也照样传。
class UploadJob {
  UploadJob({required this.file, required this.id, this.offset = 0});

  /// 服务端那个临时文件的 id。重试、续传、断点都认它。
  final String id;

  final PickedFile file;
  String get name => file.name;
  int get size => file.size;

  /// 已经确认写进服务端的字节数。卡住重试也从这儿接着来。
  int offset = 0;

  UploadState state = UploadState.queued;
  int got = 0;
  double speed = 0;
  String error = '';

  UploadCancel? _cancel;
  UploadCancel get cancel => _cancel ??= UploadCancel();

  DateTime _tick = DateTime.now();
  int _tickBytes = 0;

  bool get active =>
      state == UploadState.queued || state == UploadState.running;

  /// 还能不能接着传：失败和取消都能重来，传完的不行。
  bool get retryable =>
      state == UploadState.failed || state == UploadState.cancelled;

  double get ratio => size > 0
      ? (got / size).clamp(0.0, 1.0)
      : (state == UploadState.done ? 1 : 0);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'size': size,
    'path': file.path,
    'offset': offset,
  };
}

/// 上传队列，全 App 一份。
///
/// 放在这里而不是页面 State 里，是因为一个 1GB 的包要传十几分钟，
/// 这中间人总要干点别的——退出云盘页、去看消息、甚至退到桌面。
/// 任务挂在页面上，页面一没就跟着没了；挂在这里，谁都关不掉它。
///
/// 队列还会落盘：App 被杀掉、手机重启，回来还是这些活，
/// 已传的部分靠服务端的 .part 接着续，不用从头再来。
class UploadManager extends ChangeNotifier {
  UploadManager._();

  static final UploadManager i = UploadManager._();

  static const _key = 'cloud_upload_queue';
  static const _keep = 30;

  final List<UploadJob> jobs = [];

  /// 累计传完几个。页面靠它判断要不要刷新列表——它自己可能中途才回来。
  int doneCount = 0;
  int failedCount = 0;

  bool _started = false;
  bool _busy = false;

  /// 这一批一共有几个、成了几个、砸了几个。全干完才汇总说一句，
  /// 免得选十个文件连弹十次提示。
  int _batchTotal = 0;
  int _batchDone = 0;
  int _batchFailed = 0;
  bool _batchQuiet = false;

  UploadJob? get current {
    for (final j in jobs) {
      if (j.state == UploadState.running) return j;
    }
    for (final j in jobs) {
      if (j.state == UploadState.queued) return j;
    }
    return null;
  }

  bool get busy => current != null || _busy;

  int get queuedAfter => jobs.where((j) => j.state == UploadState.queued).length;

  /// 还在队列里（含正在传）的。
  List<UploadJob> get activeJobs => jobs.where((j) => j.active).toList();

  /// 失败了、等人决定重试还是扔掉的。
  List<UploadJob> get failedJobs => jobs.where((j) => j.retryable).toList();

  /// App 启动时叫一次：把上次没传完的队列接回来。
  Future<void> init() async {
    if (_started) return;
    _started = true;
    if (kIsWeb) return;
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw == null || raw.isEmpty) return;
      final list = jsonDecode(raw);
      if (list is! List) return;
      for (final it in list) {
        if (it is! Map) continue;
        final path = '${it['path'] ?? ''}';
        final name = '${it['name'] ?? ''}';
        final size = (it['size'] as num?)?.toInt() ?? 0;
        if (path.isEmpty || name.isEmpty) continue;
        // 文件可能已经被系统清掉（选择器的缓存目录会被回收）
        if (!File(path).existsSync()) continue;
        final job = UploadJob(
          file: PickedFile(name: name, size: size, path: path),
          id: '${it['id'] ?? Api.newUploadId()}',
          offset: (it['offset'] as num?)?.toInt() ?? 0,
        );
        job.got = job.offset;
        jobs.add(job);
      }
      if (jobs.isNotEmpty) {
        _batchTotal = jobs.length;
        _batchQuiet = true; // 上次就在传，别一开机就播报
        notifyListeners();
        unawaited(_pump());
      }
    } catch (_) {
      // 队列读不出来就当没有，不至于拦住启动
    }
  }

  void add(PickedFile f) {
    final job = UploadJob(file: f, id: Api.newUploadId());
    jobs.add(job);
    _batchTotal++;
    _trim();
    _persist();
    notifyListeners();
    unawaited(_pump());
  }

  void addAll(Iterable<PickedFile> fs) {
    for (final f in fs) {
      add(f);
    }
  }

  /// 失败或取消之后再来一次。已传的字节还在，从断点接着走。
  void retry(UploadJob job) {
    if (!job.retryable) return;
    job.state = UploadState.queued;
    job.error = '';
    job.got = job.offset;
    job._cancel = null;
    _batchTotal++;
    _persist();
    notifyListeners();
    unawaited(_pump());
  }

  /// 不传了。正在跑的中断连接，还没跑的直接从队列里去掉。
  void cancel(UploadJob job) {
    if (job.state == UploadState.running) {
      job.cancel.cancel();
      return; // 等 _run 那边收尾，状态由它改
    }
    if (!job.active) return;
    job.state = UploadState.cancelled;
    unawaited(Api.dropChunks(job.id));
    _persist();
    notifyListeners();
  }

  /// 连记录一起扔掉，不再占地方。
  void discard(UploadJob job) {
    if (job.state == UploadState.running) job.cancel.cancel();
    unawaited(Api.dropChunks(job.id));
    jobs.remove(job);
    _persist();
    notifyListeners();
  }

  Future<void> _pump() async {
    if (_busy) return;
    _busy = true;
    try {
      while (true) {
        UploadJob? next;
        for (final j in jobs) {
          if (j.state == UploadState.queued) {
            next = j;
            break;
          }
        }
        if (next == null) break;
        await _run(next);
      }
    } finally {
      _busy = false;
      _settleBatch();
    }
  }

  Future<void> _run(UploadJob job) async {
    job.state = UploadState.running;
    job.got = job.offset;
    job.speed = 0;
    job._tick = DateTime.now();
    job._tickBytes = job.offset;
    unawaited(keepAliveStart(_label(job), _pct(job)));
    notifyListeners();

    try {
      await Api.uploadFileChunked(
        job.file,
        job.id,
        from: job.offset,
        cancel: job.cancel,
        onProgress: (got, total) {
          final now = DateTime.now();
          final dt = now.difference(job._tick).inMilliseconds;
          // 上万次回调全量刷新没意义，又没有动画可看。
          if (got < total && dt < 120) {
            job.got = got;
            return;
          }
          final delta = got - job._tickBytes;
          job._tick = now;
          job._tickBytes = got;
          job.got = got;
          if (dt > 0) job.speed = delta * 1000 / dt;
          _notifyBar(job);
          notifyListeners();
        },
      );
      job.state = UploadState.done;
      job.offset = job.size;
      job.got = job.size;
      doneCount++;
      _batchDone++;
      if (_batchTotal <= 1) _say(Lc.current.uploadedDone);
    } on ApiException catch (e) {
      if (job.cancel.cancelled) {
        job.state = UploadState.cancelled;
        unawaited(Api.dropChunks(job.id));
      } else {
        job.state = UploadState.failed;
        job.error = e.message;
        job.offset = job.got; // 记住断点，重试接着来
        failedCount++;
        _batchFailed++;
      }
    } catch (e) {
      if (job.cancel.cancelled) {
        job.state = UploadState.cancelled;
        unawaited(Api.dropChunks(job.id));
      } else {
        job.state = UploadState.failed;
        job.error = _msg(e);
        job.offset = job.got;
        failedCount++;
        _batchFailed++;
      }
    }
    job.speed = 0;
    if (current == null) unawaited(keepAliveStop());
    _persist();
    notifyListeners();
  }

  /// 队列空了，把这一批的结果一次说完。
  void _settleBatch() {
    final n = _batchDone + _batchFailed;
    if (n <= 0) return;
    if (_batchQuiet) {
      _batchQuiet = false;
    } else if (_batchTotal > 1) {
      if (_batchFailed == 0) {
        _say(Lc.current.uploadedDoneAll('$_batchDone'));
      } else if (_batchDone == 0) {
        _say(Lc.current.uploadedFailedAll('$_batchFailed'));
      } else {
        _say(Lc.current.uploadedPartly('$_batchDone', '$_batchFailed'));
      }
    } else if (_batchFailed > 0) {
      _say(Lc.current.uploadFailedTapRetry);
    }
    _batchTotal = 0;
    _batchDone = 0;
    _batchFailed = 0;
  }

  String _label(UploadJob job) => job.size > 0
      ? '${job.name} · ${bytesShort(job.size)}'
      : job.name;

  String _pct(UploadJob job) => '${(job.ratio * 100).round()}%';

  /// 通知栏的刷新别跟着 120ms 走，太密。两秒一次足够看出在动。
  DateTime _barTick = DateTime.fromMillisecondsSinceEpoch(0);

  void _notifyBar(UploadJob job) {
    final now = DateTime.now();
    if (now.difference(_barTick).inMilliseconds < 2000) return;
    _barTick = now;
    unawaited(keepAliveUpdate(_label(job), '${_pct(job)}${_speedText(job)}'));
  }

  String _speedText(UploadJob job) =>
      job.speed > 0 ? ' · ${bytesShort(job.speed.round())}/s' : '';

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
          duration: const Duration(milliseconds: 1600),
        ),
      );
  }

  /// 队列落盘。只留还能继续的：传完的、扔掉的都不写。
  void _persist() {
    if (kIsWeb) return;
    final list = <Map<String, dynamic>>[];
    for (final j in jobs) {
      if (j.state == UploadState.done) continue;
      if (j.file.path == null) continue;
      list.add(j.toJson());
    }
    unawaited(() async {
      try {
        final p = await SharedPreferences.getInstance();
        if (list.isEmpty) {
          await p.remove(_key);
        } else {
          await p.setString(_key, jsonEncode(list));
        }
      } catch (_) {}
    }());
  }

  /// 只留最近几条，传完的别一直堆着。队列里的和正在传的不动。
  void _trim() {
    while (jobs.length > _keep && jobs.first.state != UploadState.running) {
      if (jobs.first.active) break;
      jobs.removeAt(0);
    }
  }

  /// 把已经了结的清掉。失败的那条留给人看一眼再清。
  void clearFinished() {
    jobs.removeWhere((j) => j.state == UploadState.done);
    _persist();
    notifyListeners();
  }
}
