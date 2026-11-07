import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

import 'upload_progress.dart';

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

/// 发出去时一边读一边报进度。MultipartFile.fromPath 是流式读盘，
/// 500MB 的包也不会先进内存；进度靠自己在流上数字节，不额外拷一份。
Future<Map<String, dynamic>> postFile(
  String url,
  Map<String, String> headers,
  PickedFile f, {
  UploadProgress? onProgress,
}) async {
  final path = f.path;
  if (path == null) throw StateError('picked file has no path');

  final mp = http.MultipartRequest('POST', Uri.parse(url));
  headers.forEach((k, v) {
    if (k.toLowerCase() != 'content-type') mp.headers[k] = v;
  });
  mp.files.add(await http.MultipartFile.fromPath('f', path, filename: f.name));

  final total = mp.contentLength;
  var got = 0;
  final counted = mp.finalize().transform(
    StreamTransformer<List<int>, List<int>>.fromHandlers(
      handleData: (chunk, sink) {
        got += chunk.length;
        onProgress?.call(got, total);
        sink.add(chunk);
      },
    ),
  );

  final req = _CountingRequest('POST', Uri.parse(url), counted, total);
  req.headers.addAll(mp.headers);

  final client = http.Client();
  try {
    // 大包在慢网下要很久，给足半小时；这中间界面上有进度条。
    final res = await client.send(req).timeout(
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
  } finally {
    client.close();
  }
}

/// 只为带上传进度用：把现成的字节流交给 http 客户端，长度先算好。
/// 客户端按网络速度拉流，我们跟着读，读多少就报多少，内存不会被灌满。
class _CountingRequest extends http.BaseRequest {
  _CountingRequest(super.method, super.url, this.body, this.length);

  final Stream<List<int>> body;
  final int length;

  @override
  int get contentLength => length;

  @override
  http.ByteStream finalize() {
    super.finalize();
    return http.ByteStream(body);
  }
}
