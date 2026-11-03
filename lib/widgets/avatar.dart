import 'package:flutter/material.dart';

import '../api.dart';

/// 圆形头像。没图或加载失败就退回名字首字母，别留一个空圈。
class CircleAvatarImg extends StatefulWidget {
  final String url;
  final String name;
  final double radius;

  const CircleAvatarImg({
    super.key,
    required this.url,
    required this.name,
    this.radius = 20,
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
    return CircleAvatar(
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
  }
}
