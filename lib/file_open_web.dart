import 'dart:html' as html;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'api.dart';

/// 网页版下载。
///
/// 以前是直接开新窗口让浏览器自己下，但云盘里的私人文件要带 token，
/// `<a href>` 带不上。所以先自己取回字节（带上 Authorization），
/// 再用 blob 交给浏览器存盘。帖子附件本来是公开的，走同一条路也不亏。
Future<void> openRemoteFile(String url, String name,
    {void Function(double)? onProgress}) async {
  final client = http.Client();
  try {
    final req = http.Request('GET', Uri.parse(url));
    final tok = Api.token;
    if (tok != null && tok.isNotEmpty) {
      req.headers['Authorization'] = 'Bearer $tok';
    }
    final res = await client.send(req);
    if (res.statusCode != 200) {
      throw Exception('download failed (${res.statusCode})');
    }
    final total = res.contentLength ?? 0;
    final buf = BytesBuilder(copy: false);
    var got = 0;
    await for (final chunk in res.stream) {
      buf.add(chunk);
      got += chunk.length;
      if (total > 0) onProgress?.call((got / total).clamp(0, 1));
    }
    final bytes = buf.takeBytes();
    final blob = html.Blob([bytes]);
    final href = html.Url.createObjectUrlFromBlob(blob);
    final a = html.AnchorElement(href: href)
      ..download = name
      ..style.display = 'none';
    html.document.body?.append(a);
    a.click();
    a.remove();
    html.Url.revokeObjectUrl(href);
  } finally {
    client.close();
  }
}
