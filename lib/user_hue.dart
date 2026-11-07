import 'package:flutter/material.dart';

import 'store.dart';

/// 一个人的主题色。
///
/// 主题色在 openbbs 里不只是「我这台设备好看」——它挂在账号上，
/// 是这个人在这里的颜色：私信气泡、头像外圈、楼层边都跟着它。
/// 没设过的人用默认档位，跟 App 默认主题色一致。
double hueOfUser(Map? u) {
  // 帖子/楼层里带的是 author_hue，用户对象上是 hue，两处都认。
  final h = u?['hue'] ?? u?['author_hue'];
  if (h is int && h >= 0) return AppState.normalizeHue(h.toDouble());
  return AppState.defaultHue;
}

/// 饱满一点的实色，用在要抢眼的地方。
Color hueSolid(double hue) =>
    HSVColor.fromAHSV(1, AppState.normalizeHue(hue), 0.85, 0.82).toColor();

/// 自己发的：实色底，白字。深色模式下压一点亮度，夜里看着不刺。
Color bubbleMineBg(double hue, bool dark) => HSLColor.fromAHSL(
  1,
  AppState.normalizeHue(hue),
  dark ? 0.40 : 0.52,
  dark ? 0.34 : 0.45,
).toColor();

Color bubbleMineFg(double hue) => Colors.white.withValues(alpha: 0.96);

/// 对方发的：同一个色相的浅底 + 同色系的深字。
/// 两个人的颜色挨着也能分清，又不会把界面刷成调色盘。
Color bubblePeerBg(double hue, bool dark) => HSLColor.fromAHSL(
  1,
  AppState.normalizeHue(hue),
  dark ? 0.26 : 0.42,
  dark ? 0.20 : 0.91,
).toColor();

Color bubblePeerFg(double hue, bool dark) => HSLColor.fromAHSL(
  1,
  AppState.normalizeHue(hue),
  dark ? 0.40 : 0.55,
  dark ? 0.90 : 0.22,
).toColor();

/// 头像外圈：细环，不遮图。
Color hueRing(double hue, bool dark) => HSLColor.fromAHSL(
  dark ? 0.85 : 1,
  AppState.normalizeHue(hue),
  dark ? 0.50 : 0.55,
  dark ? 0.62 : 0.52,
).toColor();

/// 卡片底色：跟人走。
///
/// 只染一点点色相，亮度咬着 surfaceContainerLow 上下——一眼能看出是谁的，
/// 又不至于让卡片里的正文、灰字失掉对比。深色模式下同理，往暗里染。
Color hueCardBg(double hue, bool dark) => HSLColor.fromAHSL(
  1,
  AppState.normalizeHue(hue),
  dark ? 0.34 : 0.62,
  dark ? 0.155 : 0.945,
).toColor();

/// 卡片底色，开关关着时返回 null——调用方退回默认的 surfaceContainerLow。
/// 头像外圈（[hueRing]）不看这个开关。
Color? hueCardTint(double hue, bool dark) =>
    AppState.instance.hueCards.value ? hueCardBg(hue, dark) : null;
