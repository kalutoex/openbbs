import 'dart:io';

import 'package:open_filex/open_filex.dart';

/// 把下载好的文件交给系统。手机走安装器，桌面交给默认程序。
Future<void> openLocalFile(String path) async {
  if (Platform.isAndroid || Platform.isIOS) {
    await OpenFilex.open(path);
    return;
  }
  if (Platform.isWindows) {
    await Process.start('explorer', [path], mode: ProcessStartMode.detached);
    return;
  }
  if (Platform.isMacOS) {
    await Process.start('open', [path], mode: ProcessStartMode.detached);
    return;
  }
  await Process.start('xdg-open', [path], mode: ProcessStartMode.detached);
}
