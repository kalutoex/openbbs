import 'dart:io';
import 'dart:typed_data';

import 'package:gal/gal.dart';

import 'site_config.dart';
import 'package:path_provider/path_provider.dart';

/// 把一张图存到相册（手机）或图片目录（桌面）。
/// 返回给人看的位置说明；存不下就抛异常。
Future<String> saveImageBytes(Uint8List bytes, String name) async {
  if (!Platform.isAndroid && !Platform.isIOS) {
    final dir = await _pictureDir();
    final f = File('${dir.path}/$name');
    await f.writeAsBytes(bytes);
    return f.path;
  }
  await Gal.putImageBytes(bytes, album: SiteConfig.brand);
  return '相册';
}

Future<Directory> _pictureDir() async {
  final home =
      Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
  if (home != null && home.isNotEmpty) {
    final d = Directory('$home/Pictures');
    if (await d.exists()) return d;
  }
  final support = await getApplicationSupportDirectory();
  final pic = Directory('${support.path}/图片');
  await pic.create(recursive: true);
  return pic;
}
