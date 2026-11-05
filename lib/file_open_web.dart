import 'downloads.dart';

/// 网页版：没有本地目录可写，交给浏览器。
Future<SavedFile> openRemoteFile(
  String url,
  String name, {
  void Function(double)? onProgress,
  bool? openAfter,
  String? cloudId,
}) => downloadToDevice(url, name, onProgress: onProgress);
