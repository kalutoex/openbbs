import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

/// 选中待上传的文件。手机上留本地路径，网页版留浏览器 File 对象。
class PickedFile {
  PickedFile({required this.name, required this.size, this.path});

  final String name;
  final int size;
  final String? path;
}

/// 挑一个文件。用户取消返回 null。
Future<PickedFile?> pickFile() async {
  final r = await FilePicker.pickFiles(withData: false, withReadStream: false);
  if (r == null || r.files.isEmpty) return null;
  final f = r.files.first;
  return PickedFile(name: f.name, size: f.size, path: f.path);
}

/// multipart 发出去。MultipartFile.fromPath 是一边读盘一边发，
/// 500MB 的包也不会先进内存。
Future<Map<String, dynamic>> postFile(
  String url,
  Map<String, String> headers,
  PickedFile f,
) async {
  final path = f.path;
  if (path == null) throw StateError('picked file has no path');

  final req = http.MultipartRequest('POST', Uri.parse(url));
  headers.forEach((k, v) {
    if (k.toLowerCase() != 'content-type') req.headers[k] = v;
  });
  req.files.add(await http.MultipartFile.fromPath('f', path, filename: f.name));

  // 大包在慢网下要很久，给足半小时；这中间用户能看到「正在传」。
  final res = await req.send().timeout(
    const Duration(minutes: 30),
    onTimeout: () => throw TimeoutException('upload timed out'),
  );
  final text = await res.stream.bytesToString();
  if (res.statusCode != 200) {
    String msg = 'HTTP ${res.statusCode}';
    try {
      final d = jsonDecode(text);
      if (d is Map && d['detail'] != null) msg = '${d['detail']}';
    } catch (_) {}
    throw Exception(msg);
  }
  final d = jsonDecode(text);
  if (d is! Map) throw StateError('bad response');
  return Map<String, dynamic>.from(d);
}
