import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'api.dart';
import 'open_path.dart';

/// 手机上不能直接「打开」一个网络地址：先落到临时目录，再交给系统。
///
/// 网络不稳时从断点接着下，别为了一个 300MB 的包重头再来。
Future<void> openRemoteFile(String url, String name,
    {void Function(double)? onProgress}) async {
  final dir = await getTemporaryDirectory();
  final safe = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_');
  final file = File('${dir.path}/$safe');

  var have = 0;
  if (await file.exists()) {
    // 上次下了一半就断了：文件在，就别从零开始。
    have = await file.length();
  }

  final client = http.Client();
  try {
    final req = http.Request('GET', Uri.parse(url));
    // 云盘里的私人文件要凭证；帖子附件公开，带了也无害
    final tok = Api.token;
    if (tok != null && tok.isNotEmpty) {
      req.headers['Authorization'] = 'Bearer $tok';
    }
    if (have > 0) req.headers['Range'] = 'bytes=$have-';
    final res = await client.send(req);
    final ok = res.statusCode == 200 || res.statusCode == 206;
    if (!ok) {
      throw HttpException('download failed (${res.statusCode})', uri: Uri.parse(url));
    }
    if (res.statusCode == 200 && have > 0) have = 0;
    final total = (res.contentLength ?? 0) + have;
    final sink = file.openWrite(
      mode: have > 0 && res.statusCode == 206
          ? FileMode.append
          : FileMode.write,
    );
    var got = have;
    await for (final chunk in res.stream) {
      sink.add(chunk);
      got += chunk.length;
      if (total > 0) onProgress?.call((got / total).clamp(0, 1));
    }
    await sink.close();
  } finally {
    client.close();
  }
  await openLocalFile(file.path);
}
