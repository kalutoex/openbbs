/// 手机里的文件浏览器。只有安卓有，桌面和网页退回系统选择器。
library;

export 'file_browser_io.dart' if (dart.library.js_interop) 'file_browser_web.dart';
