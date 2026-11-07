import 'package:flutter/material.dart';

/// 每个人的消息颜色。
///
/// 自己挑过色相就用挑的（users.color），没挑过就按 uid 走黄金角散开——
/// 稳定、不重样，老用户不用一个个去设也能一眼分清谁是谁。
int hueOfUser(Map<String, dynamic>? u) {
  if (u == null) return 210;
  final c = u['color'];
  if (c is int && c >= 0 && c <= 359) return c;
  final uid = (u['uid'] ?? u['id'] ?? 0) as int;
  return ((uid * 137) % 360 + 360) % 360;
}

/// 自己的气泡：实色，跟原来主题色实心那种感觉一致，一眼看出「这是我说的」。
Color bubbleMineBg(int hue, bool dark) => HSLColor.fromAHSL(
  1,
  hue.toDouble(),
  dark ? 0.40 : 0.52,
  dark ? 0.34 : 0.45,
).toColor();

/// 自己的字：白，略压一点，深底上不刺眼。
Color bubbleMineFg(int hue) => Colors.white.withValues(alpha: 0.96);

/// 对方的气泡：同色系浅底，字用同色系的深色。
/// 两个人放在一起，颜色能分开，又不会花成调色盘。
Color bubblePeerBg(int hue, bool dark) => HSLColor.fromAHSL(
  1,
  hue.toDouble(),
  dark ? 0.26 : 0.42,
  dark ? 0.20 : 0.91,
).toColor();

Color bubblePeerFg(int hue, bool dark) => HSLColor.fromAHSL(
  1,
  hue.toDouble(),
  dark ? 0.40 : 0.55,
  dark ? 0.90 : 0.22,
).toColor();

/// 选色用的 36 档色块，跟主题色那条色带同一套色相。
final List<Color> userColorSwatches = List.generate(
  36,
  (i) => HSLColor.fromAHSL(1, i * 10.0, 0.55, 0.55).toColor(),
);
