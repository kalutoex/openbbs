import 'dart:typed_data';

/// 网页版没有相册，也写不了本地目录。
Future<String> saveImageBytes(Uint8List bytes, String name) async {
  throw UnsupportedError('not supported on web — right-click the image to save it');
}
