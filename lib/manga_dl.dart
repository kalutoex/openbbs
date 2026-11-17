/// 漫画离线下载的落盘：各平台一份实现，接口一致。
///
/// io  = 安卓 / Windows / Linux / macOS（真存文件）
/// web = 浏览器，只报「不支持」
library;

export 'manga_dl_io.dart' if (dart.library.js_interop) 'manga_dl_web.dart';
