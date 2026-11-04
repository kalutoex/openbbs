/// 下载落点相关的公共定义。平台差异在 downloads_io / downloads_web。
library;

/// 存好之后的落点。[display] 是给用户看的一段，[uri]/[path] 用来打开。
class SavedFile {
  const SavedFile({required this.display, this.uri, this.path});

  final String display;
  final String? uri;
  final String? path;

  bool get canOpen =>
      (uri != null && uri!.isNotEmpty) || (path != null && path!.isNotEmpty);
}

String mimeOf(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  switch (ext) {
    case 'pdf':
      return 'application/pdf';
    case 'png':
      return 'image/png';
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'gif':
      return 'image/gif';
    case 'webp':
      return 'image/webp';
    case 'txt':
    case 'md':
    case 'log':
      return 'text/plain';
    case 'json':
      return 'application/json';
    case 'zip':
      return 'application/zip';
    case 'apk':
      return 'application/vnd.android.package-archive';
    case 'mp3':
      return 'audio/mpeg';
    case 'mp4':
      return 'video/mp4';
    default:
      return 'application/octet-stream';
  }
}

String sizeText(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
  }
  if (bytes >= 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '$bytes B';
}
