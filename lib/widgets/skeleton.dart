import 'package:flutter/material.dart';

/// 灰色占位块，轻微呼吸。用于首屏没数据时顶住版面。
class Skeleton extends StatefulWidget {
  final double? width;
  final double height;
  final double radius;

  const Skeleton({
    super.key,
    this.width,
    required this.height,
    this.radius = 4,
  });

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceContainerHighest;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: base.withValues(alpha: 0.35 + 0.35 * _c.value),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// 一条帖子占位。
class ThreadTileSkeleton extends StatelessWidget {
  const ThreadTileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Skeleton(width: 38, height: 38, radius: 19),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Skeleton(width: 120, height: 11),
                SizedBox(height: 9),
                Skeleton(height: 14),
                SizedBox(height: 7),
                Skeleton(width: 200, height: 11),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 首屏骨架列表。
class SkeletonList extends StatelessWidget {
  final int count;

  const SkeletonList({super.key, this.count = 6});

  @override
  Widget build(BuildContext context) {
    final line = Theme.of(context).colorScheme.outlineVariant;
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: count,
      separatorBuilder: (_, _) => Divider(height: 1, color: line),
      itemBuilder: (_, _) => const ThreadTileSkeleton(),
    );
  }
}
