import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' hide PickedFile;

import 'api.dart';
import 'cloud.dart';
import 'file_browser.dart';
import 'file_pick.dart';
import 'img_compress.dart';
import 'l10n/error_text.dart';
import 'l10n/l10n.dart';
import 'pages/cloud_pick_page.dart';
import 'pages/gallery_picker_page.dart';
import 'plat.dart';
import 'widgets/app_sheet.dart';
import 'widgets/file_card.dart';
import 'widgets/toast.dart';

/// 选图、选附件都从这儿走。
///
/// 以前发帖、编辑帖、私信、帖子回复各写一套，行为还不一样
/// ——发帖能从云盘挑、能翻目录，帖子回复只能弹系统小框选一个。
/// 现在只有这一份，四个地方共用。
const int kMaxImages = 9;
const int kMaxFiles = 5;
const int kMaxFileBytes = 500 * 1024 * 1024;

final ImagePicker _picker = ImagePicker();

/// 选图并压缩，最多 [room] 张。超限的那张丢掉，不整批作废。
///
/// [onCompress] 报「压完第几张」，发帖页拿它画进度条。
Future<List<Uint8List>> pickImages(
  BuildContext context, {
  required int room,
  void Function(int done, int total)? onCompress,
}) async {
  if (room <= 0) {
    if (context.mounted) _say(context, Lc.current.maxNineImages);
    return const [];
  }
  List<XFile> picked;
  try {
    // 手机上有自己的相册页就用它，网页版没有 MediaStore，退回系统选择
    picked = hasMediaStore
        ? await pickOwnGallery(context, maxCount: room)
        : await _picker.pickMultiImage();
  } catch (e) {
    if (context.mounted) _say(context, Lc.current.albumFailed('$e'));
    return const [];
  }

  final take = picked.take(room).toList();
  if (picked.length > room) {
    if (context.mounted) _say(context, Lc.current.tooManyImages('$room'));
  }
  final out = <Uint8List>[];
  var done = 0;
  for (final x in take) {
    try {
      final b = await compressOne(await x.readAsBytes());
      if (b == null) {
        if (context.mounted) _say(context, Lc.current.imageStillTooBig);
      } else {
        out.add(b);
      }
    } catch (e) {
      if (context.mounted) _say(context, Lc.current.readImageFailed('$e'));
    }
    done++;
    onCompress?.call(done, take.length);
  }
  return out;
}

/// 页面没了就别弹了。省得每处写一遍 mounted。
void _say(BuildContext context, String text) {
  if (!context.mounted) return;
  toast(context, text);
}

/// 压一张。太大压不下去的返回 null，由调用方决定是丢掉还是提示。
Future<Uint8List?> compressOne(Uint8List raw) async {
  final b = await ImgCompress.run(raw);
  return ImgCompress.tooBig(b) ? null : b;
}

/// 选附件：先问是云盘里现成的还是设备上的，再选，选完就传。
/// 返回可以直接挂到帖子/消息上的 [PostFile]。
///
/// [onUpload] 在上传某个文件前报一声名字，[onProgress] 报 0~1 的进度，
/// 页面自己拿去做转圈和进度条。中途失败就停，返回已经传好的那几个。
Future<List<PostFile>> pickFiles(
  BuildContext context, {
  required int room,
  void Function(String name)? onUpload,
  void Function(double progress)? onProgress,
}) async {
  if (room <= 0) {
    if (context.mounted) _say(context, Lc.current.attachMax('$kMaxFiles'));
    return const [];
  }

  final src = await _fileSource(context);
  if (!context.mounted || src == null) return const [];
  if (src == 'cloud') return _fromCloud(context, room);

  final List<PickedFile> picked;
  if (fileBrowserSupported) {
    final r = await Navigator.of(context).push<List<PickedFile>>(
      MaterialPageRoute(builder: (_) => const FileBrowserPage(pickOnly: true)),
    );
    picked = r ?? const <PickedFile>[];
  } else {
    final f = await pickFile();
    picked = f == null ? const <PickedFile>[] : [f];
  }
  if (!context.mounted || picked.isEmpty) return const [];

  return _upload(context, picked.take(room).toList(), onUpload, onProgress);
}

/// 附件从哪来：云盘里现成的，还是设备上挑新的。
/// 云盘的不用再传一遍，地址直接能用。
Future<String?> _fileSource(BuildContext context) {
  return showAppSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.cloud_outlined),
            title: Text(Lc.current.pickFromCloud),
            onTap: () => Navigator.of(c).pop('cloud'),
          ),
          ListTile(
            leading: const Icon(Icons.smartphone),
            title: Text(Lc.current.pickFromDevice),
            onTap: () => Navigator.of(c).pop('device'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

Future<List<PostFile>> _fromCloud(BuildContext context, int room) async {
  final picked = await Navigator.of(context).push<List<CloudFile>>(
    MaterialPageRoute(builder: (_) => CloudPickPage(maxCount: room)),
  );
  if (!context.mounted || picked == null) return const [];
  return [
    for (final f in picked.take(room))
      PostFile(url: f.url, name: f.name, size: f.size),
  ];
}

Future<List<PostFile>> _upload(
  BuildContext context,
  List<PickedFile> list,
  void Function(String name)? onUpload,
  void Function(double progress)? onProgress,
) async {
  final out = <PostFile>[];
  for (final f in list) {
    if (f.size > kMaxFileBytes) {
      if (context.mounted) _say(context, Lc.current.attachTooBig('500MB'));
      continue;
    }
    onUpload?.call(f.name);
    onProgress?.call(0);
    try {
      final r = await Api.uploadFile(
        f,
        onProgress: (got, total) {
          if (total > 0) onProgress?.call(got / total);
        },
      );
      out.add(
        PostFile(
          url: '${r['url']}',
          name: '${r['name']}',
          size: r['size'] is int ? r['size'] as int : f.size,
        ),
      );
    } on ApiException catch (e) {
      if (context.mounted) _say(context, errorText(context, e));
      return out;
    } catch (e) {
      if (context.mounted) _say(context, '$e');
      return out;
    }
  }
  return out;
}
