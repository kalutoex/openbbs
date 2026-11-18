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
///
/// 键里带自己的 uid：peerId 是每座站各自编的，光靠它两个账号会互相覆盖。
class ChatBg {
  ChatBg._();

  /// 一个会话一张。读写两边必须用这一个函数算键，别各自拼。
  static String keyOf(int myId, int peerId) => 'dm_bg_u${myId}_p$peerId';

  /// 文件路径。文件被人删了就当没设过，不报错。
  ///
  /// [legacy] 是旧版本用过的键。1.1.9+100179 到 +100181 那几版里，聊天页按
  /// peerId 读、聊天信息页按 threadId 写，看着就是「设了背景但存不住」。
  /// 读的时候顺手把旧键搬过来，搬完删掉，用户不用重设一次。
  static Future<String?> pathOf(
    String key, {
    List<String> legacy = const [],
  }) async {
    final p = await SharedPreferences.getInstance();
    var path = p.getString(key);
    if (path == null || path.isEmpty) {
      for (final k in legacy) {
        final old = p.getString(k);
        if (old == null || old.isEmpty) continue;
        if (await _alive(old)) {
          await p.setString(key, old);
          path = old;
          await p.remove(k);
          break;
        }
        await p.remove(k);
      }
    }
    if (path == null || path.isEmpty) return null;
    return await _alive(path) ? path : null;
  }

  /// 从相册挑一张。返回新路径，取消返回 null。
  static Future<String?> pick(String key) async {
    final f = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2000,
      imageQuality: 90,
    );
    if (f == null) return null;
    final sup = await getApplicationSupportDirectory();
    final dir = Directory('${sup.path}/chat_bg');
    if (!await dir.exists()) await dir.create(recursive: true);
    final dst = '${dir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await File(f.path).copy(dst);
    final p = await SharedPreferences.getInstance();
    final old = p.getString(key);
    await p.setString(key, dst);
    // 换下来的那张顺手删掉，别在应用目录里堆着。
    if (old != null && old != dst) await _drop(old);
    return dst;
  }

  static Future<void> clear(
    String key, {
    List<String> legacy = const [],
  }) async {
    final p = await SharedPreferences.getInstance();
    final gone = <String>{};
    final old = p.getString(key);
    if (old != null) gone.add(old);
    await p.remove(key);
    for (final k in legacy) {
      final v = p.getString(k);
      if (v != null) gone.add(v);
      await p.remove(k);
    }
    for (final f in gone) {
      await _drop(f);
    }
  }

  static Future<bool> _alive(String path) async {
    try {
      return await File(path).exists();
    } catch (_) {
      return false;
    }
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
