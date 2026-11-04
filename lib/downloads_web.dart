import 'dart:html' as html;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'api.dart';
import 'downloads_common.dart';

/// 网页版的下载位置不归我们管：文件进浏览器自己的下载目录，
/// 由它按设置去问、去存。这里只负责把字节和文件名交过去。

class DownloadPrefs {
  static Future<bool> autoOpen() async => false;

  static Future<void> setAutoOpen(bool v) async {}

  /// 网页版没有「下载位置」可设置，设置页据此把这一项藏起来。
  static Future<String> label() async => '';

  static Future<void> setDir(String? id, String? label) async {}
}

Future<String?> pickDownloadDir() async => null;

Future<void> resetDownloadDir() async {}

Future<SavedFile> saveDownloaded(String tmpPath, String name) async =>
    SavedFile(display: name);

Future<void> openSaved(SavedFile f) async {}

/// 取回字节（带上 token），再用 blob 交给浏览器存盘。
///
/// 以前是开新窗口让浏览器自己下，但云盘里的私人文件要凭证，
/// `<a href>` 带不上 header，只能自己先拿回来。
Future<SavedFile> downloadToDevice(String url, String name,
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
      throw http.ClientException('下载失败（${res.statusCode}）', Uri.parse(url));
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
  return SavedFile(display: name);
}

Future<int> downloadCacheSize() async => 0;

Future<void> clearDownloadCache() async {}
