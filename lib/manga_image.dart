/// 本机图片：io 读文件，web 没有这回事（见 manga_image_web.dart）。
library;

export 'manga_image_io.dart' if (dart.library.js_interop) 'manga_image_web.dart';
