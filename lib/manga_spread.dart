/// 双页并排的换算规则。
///
/// 阅读器里「第几页」是按单页算的（续读、上报、跳页都用它），
/// 一屏两页时只是把两页摆在一起——所以页码和屏号要能来回换，
/// 换算写在这里，阅读器只调不算，单测也盯得住。
class MangaSpread {
  /// 一屏几页。条漫和拆页时永远一页：条漫是连着滚的，
  /// 拆分已经把一张跨页图切成两屏了，再并排就成了四块。
  static int per({
    required bool spread,
    required bool vertical,
    required bool split,
  }) {
    if (!spread || vertical || split) return 1;
    return 2;
  }

  /// 一共几屏。
  static int screens(int pages, int per) {
    if (per <= 1 || pages <= 0) return pages;
    return (pages + per - 1) ~/ per;
  }

  /// 第 [page] 页落在第几屏。
  static int screenOf(int page, int per) => per <= 1 ? page : page ~/ per;

  /// 第 [screen] 屏从第几页起。
  static int pageOf(int screen, int per) => per <= 1 ? screen : screen * per;

  /// 底栏那个页码：单页是 `12 / 45`，双页是 `12-13 / 45`。
  static String label(int page, int total, int per) {
    if (per <= 1 || total <= 0) return '${page + 1} / $total';
    final a = page + 1;
    final b = (page + per).clamp(0, total);
    return b > a ? '$a-$b / $total' : '$a / $total';
  }
}
