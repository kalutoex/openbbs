import 'dart:typed_data';

/// 网页版没有相册，也写不了本地目录。
Future<String> saveImageBytes(Uint8List bytes, String name) async {
  throw UnsupportedError('网页版存不了，右键图片另存');
}
