/// 下载落点：各平台一份实现，接口一致。
///
/// io  = 安卓 / Windows / Linux / macOS
/// web = 浏览器，位置由浏览器自己决定
library;

export 'downloads_common.dart';
export 'downloads_io.dart' if (dart.library.js_interop) 'downloads_web.dart';
