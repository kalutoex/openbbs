import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'cancel_token.dart';

/// 漫画离线下载的落盘那一半：文件、字节、剩余空间。
///
/// 只做「往这张盘上读写」这件事，任务队列和索引格式在 manga_download.dart。
/// 网页版没有这张盘（见 manga_dl_web.dart），那边全部报不支持。
bool get mangaDlOk => true;

/// `<appSupport>/manga/<站点>`。站点用一个干净名字，别把 URL 里的 / 带进路径。
Future<String> mangaDlRoot(String site) async {
  final sup = await getApplicationSupportDirectory();
  return '${sup.path}/manga/${_safe(site)}';
}

String _safe(String s) {
  final t = s.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  return t.isEmpty ? 'default' : t;
}

Future<String?> mangaDlReadIndex(String root) async {
  try {
    final f = File('$root/index.json');
    if (!await f.exists()) return null;
    return await f.readAsString();
  } catch (_) {
    return null;
  }
}

/// 写索引：先写 .tmp 再改名，写到一半被杀进程也不会留下半截 JSON。
Future<void> mangaDlWriteIndex(String root, String body) async {
  final dir = Directory(root);
  if (!await dir.exists()) await dir.create(recursive: true);
  final tmp = File('$root/index.json.tmp');
  await tmp.writeAsString(body, flush: true);
  await tmp.rename('$root/index.json');
}

/// 索引读不出来（文件坏了）时把它挪到一边，留个现场，别一直卡在那儿。
Future<void> mangaDlQuarantineIndex(String root) async {
  try {
    final f = File('$root/index.json');
    if (await f.exists()) {
      await f.rename('$root/index.json.bad');
    }
  } catch (_) {}
}

Future<bool> mangaDlExists(String path) => File(path).exists();

Future<int> mangaDlSize(String path) async {
  try {
    return await File(path).length();
  } catch (_) {
    return 0;
  }
}

Future<void> mangaDlRemoveTree(String path) async {
  final d = Directory(path);
  if (!await d.exists()) return;
  await d.delete(recursive: true);
}

Future<void> mangaDlMove(String from, String to) async {
  await File(from).rename(to);
}

Future<int> mangaDlDeleteFile(String path) async {
  try {
    final f = File(path);
    if (!await f.exists()) return 0;
    final n = await f.length();
    await f.delete();
    return n;
  } catch (_) {
    return 0;
  }
}

/// 这张盘还剩多少字节。问不到就是 -1（外置盘、某些定制系统）。
Future<int> mangaDlFreeBytes() async {
  try {
    final sup = await getApplicationSupportDirectory();
    // 问到的是应用目录所在的那块盘
    return await _freeOf(sup.path);
  } catch (_) {
    return -1;
  }
}

Future<int> _freeOf(String path) async {
  final r = await Process.run('df', ['-k', path]);
  if (r.exitCode != 0) return -1;
  final lines = '${r.stdout}'.trim().split('\n');
  if (lines.length < 2) return -1;
  final cols = lines.last.trim().split(RegExp(r'\s+'));
  if (cols.length < 4) return -1;
  final avail = int.tryParse(cols[3]);
  return avail == null ? -1 : avail * 1024;
}

/// 一话的图。串行取、逐页落盘，.part 续传。
///
/// 返回这轮真正写进去的字节数。[onPage] 每完成一页（含本来就有的）报一次。
Future<int> mangaDlFetchChapter({
  required String destDir,
  required List<String> urls,
  required List<String> names,
  required CancelToken cancel,
  required void Function(int done, int total) onPage,
}) async {
  final dir = Directory(destDir);
  if (!await dir.exists()) await dir.create(recursive: true);
  final client = http.Client();
  cancel.onCancel(() => client.close());
  var written = 0;
  try {
    for (var i = 0; i < urls.length; i++) {
      if (cancel.cancelled) break;
      final finalPath = '$destDir/${names[i]}';
      final done = File(finalPath);
      if (await done.exists() && await done.length() > 0) {
        onPage(i + 1, urls.length);
        continue;
      }
      written += await _one(client, urls[i], finalPath, cancel);
      onPage(i + 1, urls.length);
    }
  } finally {
    client.close();
  }
  return written;
}

/// 单页下载，最多三次（首次 + 两次重试，间隔 1s / 3s）。
///
/// 中断/失败留着 `<name>.part`：下次从已有的字节往后要（Range）。
/// 后端这类图不支持 Range 也没关系，退回整张重来，只是多花点流量。
Future<int> _one(
  http.Client client,
  String url,
  String finalPath,
  CancelToken cancel,
) async {
  final part = File('$finalPath.part');
  var have = await part.exists() ? await part.length() : 0;
  Object? last;
  for (var attempt = 0; attempt < 3; attempt++) {
    if (cancel.cancelled) throw const _Cancelled();
    try {
      if (have > 0) {
        final r = await _get(client, url, from: have);
        if (r.statusCode == 206) {
          await part.writeAsBytes(r.bodyBytes, mode: FileMode.append, flush: true);
          have += r.bodyBytes.length;
        } else if (r.statusCode == 200) {
          // 不认 Range，整张重来
          await part.writeAsBytes(r.bodyBytes, flush: true);
          have = r.bodyBytes.length;
        } else {
          throw HttpException('HTTP ${r.statusCode}');
        }
      } else {
        final r = await _get(client, url);
        if (r.statusCode != 200) throw HttpException('HTTP ${r.statusCode}');
        await part.writeAsBytes(r.bodyBytes, flush: true);
        have = r.bodyBytes.length;
      }
      if (have <= 0) throw const HttpException('空图');
      await part.rename(finalPath);
      return have;
    } on _Cancelled {
      rethrow;
    } catch (e) {
      last = e;
      have = await part.exists() ? await part.length() : 0;
      if (attempt == 2) break;
      await Future<void>.delayed(Duration(seconds: attempt == 0 ? 1 : 3));
    }
  }
  throw StateError('这一页取不下来：$last');
}

Future<http.Response> _get(http.Client client, String url, {int from = 0}) {
  final req = http.Request('GET', Uri.parse(url));
  req.headers['User-Agent'] = 'OpenBBS-manga-dl';
  if (from > 0) req.headers['Range'] = 'bytes=$from-';
  return client
      .send(req)
      .then(http.Response.fromStream)
      .timeout(const Duration(seconds: 45));
}

class _Cancelled implements Exception {
  const _Cancelled();
}
