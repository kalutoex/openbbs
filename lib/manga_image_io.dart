import 'dart:io';

import 'package:flutter/material.dart';

/// 本机文件当图用：io 上有，web 上没有。
///
/// 漫画阅读器一页要么是网络地址，要么是已经下到手机里的文件。这层只负责
/// 「给我一个路径，能画就画」，判空和回落由调用方做。
Widget? mangaFileImage(
  String path, {
  required BoxFit fit,
  Alignment alignment = Alignment.center,
  Widget Function()? fallback,
}) {
  final f = File(path);
  return Image.file(
    f,
    fit: fit,
    alignment: alignment,
    gaplessPlayback: true,
    errorBuilder: (_, _, _) => fallback?.call() ?? const SizedBox.shrink(),
  );
}

ImageProvider? mangaFileProvider(String path) {
  final f = File(path);
  if (!f.existsSync()) return null;
  return FileImage(f);
}
