import 'package:flutter/material.dart';

import 'avatar.dart';

/// 列表里的一行用户：头像 + 名字 + 一行副标题。
///
/// 账号、好友、搜索三处以前各拼一份，除了半径和字号没别的差别。
/// 私信会话和关注列表的样式跟这个差得远，各自留在页面里。
class UserTile extends StatelessWidget {
  const UserTile({
    super.key,
    required this.name,
    this.avatar = '',
    this.hue,
    this.subtitle,
    this.radius = 20,
    this.nameStyle,
    this.subtitleStyle,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.shape,
  });

  final String name;
  final String avatar;
  final double? hue;
  final String? subtitle;
  final double radius;
  final TextStyle? nameStyle;
  final TextStyle? subtitleStyle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final ShapeBorder? shape;

  @override
  Widget build(BuildContext context) {
    final sub = subtitle;
    return ListTile(
      shape: shape,
      leading: CircleAvatarImg(
        url: avatar,
        name: name,
        radius: radius,
        hue: hue,
      ),
      title: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: nameStyle,
      ),
      subtitle: sub == null || sub.isEmpty
          ? null
          : Text(
              sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: subtitleStyle,
            ),
      trailing: trailing,
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}
