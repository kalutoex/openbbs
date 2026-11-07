/// 一个能传到别处的「取消」开关。
///
/// 上传和下载都要用：用户点了「×」，得能把正在跑的连接掐掉，
/// 而不是等它自己传完再假装取消。底层 http client 的 close 挂在这里。
class CancelToken {
  CancelToken();

  bool _c = false;
  final List<void Function()> _hooks = [];

  bool get cancelled => _c;

  /// 已经在取消之后再挂，立刻执行——避免「刚点取消，连接才建好」这种缝隙。
  void onCancel(void Function() hook) {
    if (_c) {
      hook();
    } else {
      _hooks.add(hook);
    }
  }

  void cancel() {
    if (_c) return;
    _c = true;
    for (final h in List.of(_hooks)) {
      try {
        h();
      } catch (_) {}
    }
    _hooks.clear();
  }
}
