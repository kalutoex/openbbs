import 'package:flutter/material.dart';

/// 轻提示，统一 1.5 秒。
///
/// 新提示直接顶掉旧的，不排队——连着点两下不会各自等满一轮。
/// 原来就浮在底部的调用点传 floating，别让它们突然变成贴底的一条。
void toast(
  BuildContext context,
  String text, {
  SnackBarAction? action,
  bool floating = false,
}) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(text),
        duration: const Duration(milliseconds: 1500),
        behavior: floating ? SnackBarBehavior.floating : null,
        action: action,
      ),
    );
}
