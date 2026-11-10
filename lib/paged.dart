/// 一页一页往回拉的列表状态。
///
/// 十三个列表页以前各写一份：items / page / busy / hasMore / first / err
/// 六个字段，加一份几乎一样的 reload、一份几乎一样的 loadMore。
/// 差别只在「一页多大」和「怎么判断还有没有下一页」，那就只留这两个参数。
///
/// 页面仍然是自己的：谁在什么时候刷新、错了是弹窗还是留着旧数据，
/// 由页面决定，这里只负责「拉第几页、拼上去、别把旧请求的结果拼进来」。
library;

/// 一页的结果。[hasMore] 空着就按「不满一页即到底」判断。
class PageSlice<T> {
  const PageSlice(this.items, {this.hasMore});

  final List<T> items;
  final bool? hasMore;
}

class Pager<T> {
  Pager({required this.fetch, this.size = 20});

  /// 拉第 page 页（从 1 开始）。
  final Future<PageSlice<T>> Function(int page) fetch;

  /// 一页几条，用来判断到底。服务端给了 hasMore 就听服务端的。
  final int size;

  final List<T> items = [];

  /// 有请求在飞。翻页时不重复发。
  bool busy = false;

  /// 正在拉下一页。列表底部靠它决定转不转圈——
  /// 用的不是 busy，否则下拉刷新时底部也会跟着转。
  bool loadingMore = false;
  bool hasMore = true;

  /// 还没拉到第一页。
  bool first = true;

  /// 上一次失败的原因，页面自己决定怎么显示；成功就清掉。
  Object? error;

  int _page = 1;

  /// 请求代号：刷新会换号，旧请求回来自动作废，
  /// 否则刷新后旧页会拼到新列表上。
  int _seq = 0;

  bool get isEmpty => items.isEmpty;
  bool get isNotEmpty => items.isNotEmpty;

  /// 从头来一遍。
  ///
  /// 不先清空：清空和重建之间只要有一次重绘，itemBuilder 就会拿到
  /// 越界的下标。旧列表撑到新数据回来再整块换掉，顺带也不闪。
  Future<void> reset() async {
    final seq = ++_seq;
    if (items.isEmpty) first = true;
    _page = 1;
    hasMore = true;
    error = null;
    busy = true;
    try {
      final s = await fetch(1);
      if (seq != _seq) return;
      items
        ..clear()
        ..addAll(s.items);
      _page = 2;
      hasMore = s.hasMore ?? s.items.length >= size;
      first = false;
    } catch (e) {
      if (seq != _seq) return;
      first = false;
      error = e;
    } finally {
      if (seq == _seq) {
        busy = false;
        loadingMore = false;
      }
    }
  }

  /// 拉下一页。已经在拉或者到底了就直接返回。
  Future<void> more() async {
    if (busy || !hasMore) return;
    final seq = _seq;
    busy = true;
    loadingMore = true;
    try {
      final s = await fetch(_page);
      if (seq != _seq) return;
      items.addAll(s.items);
      _page++;
      hasMore = s.hasMore ?? s.items.length >= size;
      error = null;
    } catch (e) {
      if (seq != _seq) return;
      error = e;
    } finally {
      if (seq == _seq) busy = false;
    }
  }

  /// 错误已经给用户看过了，擦掉，别下次 build 又弹一遍。
  void clearError() => error = null;

  /// 本地改完之后重新拉。删掉一条、改一条，走这个最省事。
  /// 会清空列表，所以调用方得包在 setState 里。
  void invalidate() {
    _seq++;
    _page = 1;
    hasMore = true;
    items.clear();
    first = true;
    error = null;
    busy = false;
  }
}
