import 'package:flutter/material.dart';

import '../api.dart';
import '../user_hue.dart';

/// 圆形头像。没图或加载失败就退回名字首字母，别留一个空圈。
///
/// 传了 [hue] 就在外面套一圈这个人的主题色——头像圈是认人的第一眼，
/// 不用等看到名字才知道是谁。
class CircleAvatarImg extends StatefulWidget {
  final String url;
  final String name;
  final double radius;

  /// 这个人的主题色色相。null = 不画圈（工具栏、账号切换这种地方）。
  final double? hue;

  const CircleAvatarImg({
    super.key,
    required this.url,
    required this.name,
    this.radius = 20,
    this.hue,
  });

  @override
  State<CircleAvatarImg> createState() => _CircleAvatarImgState();
}

class _CircleAvatarImgState extends State<CircleAvatarImg> {
  bool _bad = false;

  @override
  void didUpdateWidget(CircleAvatarImg old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) _bad = false;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final show = widget.url.isNotEmpty && !_bad;
    // 头像按显示尺寸解码。不这么做的话 1000px 的原图会整张进内存，
    // 一个帖子 20 个头像就是几百兆。
    final px = (widget.radius * 2 * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(32, 256);
    final av = CircleAvatar(
      radius: widget.radius,
      backgroundColor: cs.primaryContainer,
      backgroundImage: show
          ? ResizeImage(NetworkImage(Api.img(widget.url)), width: px)
          : null,
      onBackgroundImageError: show
          ? (_, _) {
              if (mounted) setState(() => _bad = true);
            }
          : null,
      child: show
          ? null
          : Text(
              widget.name.isEmpty ? '?' : widget.name.characters.first,
              style: TextStyle(
                fontSize: widget.radius * 0.8,
                color: cs.onPrimaryContainer,
              ),
            ),
    );
    final hue = widget.hue;
    if (hue == null) return av;
    // 环压在头像外沿：内边距 2、描边 2，半径算下来比原图大 4，不至于被遮住。
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: hueRing(hue, Theme.of(context).brightness == Brightness.dark),
          width: 2,
        ),
      ),
      child: av,
    );
  }
}
