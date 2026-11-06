/// 本地文件的位置与存在性。只有 io 平台有意义，web 那边一律当没有。
library;

export 'local_files_io.dart'
    if (dart.library.js_interop) 'local_files_web.dart';
