import 'package:flutter/material.dart';

/// 网页版：背景换不了。
///
/// 浏览器里没有可靠的地方放这张图（一刷新就没了，除非塞进 IndexedDB），
/// 也没必要为一个装饰性的东西引一套本地库。这里全当没设过，
/// 界面上那个入口会直接告诉人「网页版暂时换不了」。
///
/// 接口要和 io 那份对齐：键怎么算也放在这里，两边同一个签名，
/// 免得各页各拼一套字符串，又拼不到一块去。
class ChatBg {
  ChatBg._();

  static String keyOf(int myId, int peerId) => 'dm_bg_u${myId}_p$peerId';

  static Future<String?> pathOf(
    String key, {
    List<String> legacy = const [],
  }) async => null;

  static Future<String?> pick(String key) async => null;

  static Future<void> clear(
    String key, {
    List<String> legacy = const [],
  }) async {}

  static Widget image(BuildContext context, String path) =>
      const SizedBox.shrink();
}
