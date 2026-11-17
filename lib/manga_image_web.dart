import 'package:flutter/material.dart';

/// 网页版读不到本机文件（离线下载在那边本来就不支持），一律返回 null，
/// 调用方会回落到网络那张图。
Widget? mangaFileImage(
  String path, {
  required BoxFit fit,
  Alignment alignment = Alignment.center,
  Widget Function()? fallback,
}) => null;

ImageProvider? mangaFileProvider(String path) => null;
