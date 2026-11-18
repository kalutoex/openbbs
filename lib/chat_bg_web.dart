import 'package:flutter/material.dart';

/// 网页版：背景换不了。
///
/// 浏览器里没有可靠的地方放这张图（一刷新就没了，除非塞进 IndexedDB），
/// 也没必要为一个装饰性的东西引一套本地库。这里全当没设过，
/// 界面上那个入口会直接告诉人「网页版暂时换不了」。
class ChatBg {
  ChatBg._();

  static Future<String?> pathOf(int tid) async => null;

  static Future<String?> pick(int tid) async => null;

  static Future<void> clear(int tid) async {}

  static Widget image(BuildContext context, String path) =>
      const SizedBox.shrink();
}
