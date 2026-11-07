import 'package:flutter/material.dart';

/// 一页里并排的几栏：顶上胶囊分段控件，指示块跟着手指走，
/// 下面 PageView 跟手翻，松手吸附。
///
/// 原来关注/粉丝是自己画的指示块配 IndexedStack（不能滑），
/// 传输页和回收站是 TabBar 配 TabBarView（能滑但长得不一样）。
/// 现在三处都用这一个，样式和手感统一。
class SegmentedPages extends StatefulWidget {
  const SegmentedPages({
    super.key,
    required this.labels,
    required this.children,
    this.counts,
    this.initial = 0,
    this.onChanged,
    this.padding = const EdgeInsets.fromLTRB(16, 6, 16, 10),
  });

  final List<String> labels;
  final List<Widget> children;

  /// 每个标签右边的数字，0 就不显示。
  final List<int>? counts;

  final int initial;

  /// 翻到第几页了。外面要跟着改标题、换按钮就用这个。
  final ValueChanged<int>? onChanged;

  final EdgeInsets padding;

  @override
  State<SegmentedPages> createState() => _SegmentedPagesState();
}

class _SegmentedPagesState extends State<SegmentedPages> {
  late final PageController _pc = PageController(initialPage: widget.initial);
  late int _i = widget.initial;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  void _to(int i) {
    if (i == _i) return;
    _pc.animateToPage(
      i,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final n = widget.children.length;
    return Column(
      children: [
        Padding(
          padding: widget.padding,
          child: Container(
            height: 40,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(11),
            ),
            child: LayoutBuilder(
              builder: (context, cons) {
                final w = cons.maxWidth / n;
                return AnimatedBuilder(
                  animation: _pc,
                  builder: (context, _) {
                    // 手指拖到哪指示块就跟到哪。还没量出尺寸时按选中的那栏摆。
                    final p =
                        _pc.hasClients && _pc.position.hasContentDimensions
                        ? (_pc.page ?? _i.toDouble())
                        : _i.toDouble();
                    return Stack(
                      children: [
                        Positioned(
                          left: p * w,
                          top: 0,
                          bottom: 0,
                          width: w,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: cs.surface,
                              borderRadius: BorderRadius.circular(9),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 3,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            for (var i = 0; i < n; i++)
                              Expanded(
                                child: _seg(
                                  context,
                                  widget.labels[i],
                                  (widget.counts != null &&
                                          i < widget.counts!.length)
                                      ? widget.counts![i]
                                      : 0,
                                  i,
                                ),
                              ),
                          ],
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ),
        Expanded(
          child: PageView(
            controller: _pc,
            onPageChanged: (i) {
              if (!mounted) return;
              setState(() => _i = i);
              widget.onChanged?.call(i);
            },
            children: [for (final c in widget.children) _Keep(child: c)],
          ),
        ),
      ],
    );
  }

  Widget _seg(BuildContext context, String label, int count, int index) {
    final cs = Theme.of(context).colorScheme;
    final on = _i == index;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _to(index),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                color: on ? cs.onSurface : cs.onSurfaceVariant,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 5),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 12,
                  color: on ? cs.primary : cs.outline,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 滑走的那栏别把状态扔了，回来还在原处。
class _Keep extends StatefulWidget {
  const _Keep({required this.child});

  final Widget child;

  @override
  State<_Keep> createState() => _KeepState();
}

class _KeepState extends State<_Keep> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
