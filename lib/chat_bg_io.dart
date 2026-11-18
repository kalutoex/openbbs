import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 聊天背景：一张图，只存在这台手机上。
///
/// 不上传服务器，对方看不到，换手机也不会带过去——跟微信那个「设置当前聊天背景」
/// 一个意思，只是那份记录存在本地。
///
/// 原图挑完复制进应用目录再记路径：相册里那张被删、被清理软件扫掉，
/// 背景不至于跟着白掉。
class ChatBg {
  ChatBg._();

  /// 按会话记，一个会话一张。用 threadId 做键，跟人换号、改名都不受影响。
  static String _key(int tid) => 'dm_bg_$tid';

  /// 文件路径。文件被人删了就当没设过，不报错。
  static Future<String?> pathOf(int tid) async {
    final p = await SharedPreferences.getInstance();
    final path = p.getString(_key(tid));
    if (path == null || path.isEmpty) return null;
    try {
      if (await File(path).exists()) return path;
    } catch (_) {}
    return null;
  }

  /// 从相册挑一张。返回新路径，取消返回 null。
  static Future<String?> pick(int tid) async {
    final f = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2000,
      imageQuality: 90,
    );
    if (f == null) return null;
    final sup = await getApplicationSupportDirectory();
    final dir = Directory('${sup.path}/chat_bg');
    if (!await dir.exists()) await dir.create(recursive: true);
    final dst =
        '${dir.path}/$tid-${DateTime.now().millisecondsSinceEpoch}.jpg';
    await File(f.path).copy(dst);
    final p = await SharedPreferences.getInstance();
    final old = p.getString(_key(tid));
    await p.setString(_key(tid), dst);
    // 换下来的那张顺手删掉，别在应用目录里堆着。
    if (old != null && old != dst) await _drop(old);
    return dst;
  }

  static Future<void> clear(int tid) async {
    final p = await SharedPreferences.getInstance();
    final old = p.getString(_key(tid));
    await p.remove(_key(tid));
    if (old != null) await _drop(old);
  }

  static Future<void> _drop(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// 铺满聊天区的那张图。暗色下压一点，白底气泡不至于浮在上面看不见边。
  static Widget image(BuildContext context, String path) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
      color: dark ? Colors.black.withValues(alpha: .35) : null,
      colorBlendMode: dark ? BlendMode.darken : null,
    );
  }
}
