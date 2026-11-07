import 'package:flutter/foundation.dart';

import 'cancel_token.dart';
import 'downloads.dart';
import 'file_open.dart';

/// 一个正在下的东西。
class DownloadJob {
  DownloadJob({required this.key, required this.name, required this.total});

  /// 认这一份用的键：云盘的是 `cloud:<id>`，别处来的按地址。
  final String key;

  /// 文件名，列表里显示这个。
  final String name;

  /// 云端说的大小，不知道就是 0。
  final int total;

  /// 0..1。还没开始动的时候是 0。
  double progress = 0;

  /// 点了取消就是 true。调用方靠它把「取消」和「出错」分开。
  bool cancelled = false;

  CancelToken get token => _token;
  final CancelToken _token = CancelToken();

  /// 已经收了多少字节。总量不知道的时候这里是 null。
  int? get received =>
      total > 0 ? (total * progress).round().clamp(0, total) : null;
}

/// 下载队列。
///
/// 跟 UploadManager 一个路子：状态不放页面里，退出云盘页下载照旧在跑，
/// 传输页也能看见同一份进度。一次能同时下几个，各自算各自的。
class DownloadManager extends ChangeNotifier {
  DownloadManager._();

  static final DownloadManager i = DownloadManager._();

  final Map<String, DownloadJob> _jobs = <String, DownloadJob>{};

  /// 正在下的，按开始先后排。
  List<DownloadJob> get jobs => List.unmodifiable(_jobs.values);

  bool get busy => _jobs.isNotEmpty;

  static String keyForCloud(int id) => 'cloud:$id';

  DownloadJob? of(String key) => _jobs[key];

  bool isDownloading(String key) => _jobs.containsKey(key);

  double? progressOf(String key) => _jobs[key]?.progress;

  /// 下一个。已经在下的同一个文件不会再起一份。
  ///
  /// 取消的时候返回 null，别的地方照常抛错。
  Future<SavedFile?> start(
    String key,
    String url,
    String name, {
    int total = 0,
    String? cloudId,
  }) async {
    if (_jobs.containsKey(key)) return null;
    final job = DownloadJob(key: key, name: name, total: total);
    _jobs[key] = job;
    notifyListeners();
    try {
      return await openRemoteFile(
        url,
        name,
        cloudId: cloudId,
        cancel: job.token,
        onProgress: (p) {
          job.progress = p;
          notifyListeners();
        },
      );
    } on Object {
      if (job.cancelled) return null;
      rethrow;
    } finally {
      // 取消那一头已经把这个删了也不要紧，重复删无害
      _jobs.remove(key);
      notifyListeners();
    }
  }

  /// 不下了。连接掐掉，半截文件由底层收拾。
  void cancel(String key) {
    final job = _jobs.remove(key);
    if (job == null) return;
    job.cancelled = true;
    job.token.cancel();
    notifyListeners();
  }

  void cancelAll() {
    for (final key in List.of(_jobs.keys)) {
      cancel(key);
    }
  }
}
