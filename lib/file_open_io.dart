import 'dart:io';

import 'cancel_token.dart';
import 'download_index.dart';
import 'downloads.dart';

/// 点「下载」：文件落到用户找得到的地方，再按设置决定要不要立刻打开。
///
/// 以前是下到临时目录直接开，用户根本不知道文件在哪、系统又会清掉，
/// 现在改成先存到下载位置（设置里能改），存完报一句「已保存到 xxx」。
///
/// 返回 [SavedFile]，调用方拿 display 去提示。
/// [cloudId] 是从云盘下的那个文件的 id；记下来，回云盘页能认出来点过。
Future<SavedFile> openRemoteFile(
  String url,
  String name, {
  void Function(double)? onProgress,
  bool? openAfter,
  String? cloudId,
  CancelToken? cancel,
}) async {
  final saved = await downloadToDevice(url, name,
      onProgress: onProgress, cancel: cancel);
  var size = 0;
  final p = saved.path;
  if (p != null && p.isNotEmpty) {
    try {
      size = await File(p).length();
    } catch (_) {
      // 量不到就算了，列表里显示 -- 而已
    }
  }
  await rememberLocalDownload(saved, size: size, cloudId: cloudId);
  final shouldOpen = openAfter ?? await DownloadPrefs.autoOpen();
  if (shouldOpen) {
    try {
      await openSaved(saved);
    } catch (_) {
      // 打开失败不影响已经存下来的文件，提示里的路径照样能用
    }
  }
  return saved;
}
