// 网页端的实现，只在 web 编译时进来。dart:html 已标记废弃，但换成
// package:web 要把这里的 Stream 写法全改成 addEventListener，
// 改坏了网页版的上传下载是哑巴故障，先留着，等 Flutter 真移除再一并迁。
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

import 'cancel_token.dart';
import 'upload_progress.dart';

/// 选中待上传的文件。网页版拿的是浏览器里的 File，文件本身还在磁盘上。
class PickedFile {
  PickedFile({required this.name, required this.size, this.path, this.file});

  final String name;
  final int size;

  /// 网页上没有本地路径，这个永远是 null。管理器看到没路径就走整传。
  /// 留着这个字段只是为了让两边共用的代码编译得过。
  final String? path;

  final html.File? file;
}

/// 网页版的选文件：一个隐藏的 file input。
///
/// 不用 file_picker 的 withData —— 那个会把整个文件读成字节，
/// 传 500MB 的包时浏览器直接吃掉 500MB 内存。这里只要 File 句柄，
/// 真正的读取交给浏览器边传边读。
Future<PickedFile?> pickFile() async {
  final input = html.FileUploadInputElement();
  final done = Completer<PickedFile?>();
  input.style.display = 'none';
  html.document.body?.children.add(input);

  void finish(PickedFile? v) {
    input.remove();
    if (!done.isCompleted) done.complete(v);
  }

  input.onChange.listen((_) {
    final list = input.files;
    if (list == null || list.isEmpty) {
      finish(null);
      return;
    }
    final f = list.first;
    finish(PickedFile(name: f.name, size: f.size, file: f));
  });
  input.onError.listen((_) => finish(null));
  input.click();
  return done.future;
}

/// XHR + FormData：浏览器直接从磁盘流式上传，进度也拿得到。
Future<Map<String, dynamic>> postFile(
  String url,
  Map<String, String> headers,
  PickedFile f, {
  UploadProgress? onProgress,
}) {
  final blob = f.file;
  if (blob == null) throw StateError('picked file has no blob');
  final form = html.FormData()..appendBlob('f', blob, f.name);
  final req = html.HttpRequest();
  final done = Completer<Map<String, dynamic>>();

  req.open('POST', url);
  headers.forEach((k, v) {
    if (k.toLowerCase() != 'content-type') req.setRequestHeader(k, v);
  });
  req.timeout = 30 * 60 * 1000;
  // 浏览器自己从磁盘读，这里只报它已经发出去多少。
  req.upload.onProgress.listen((e) {
    onProgress?.call(e.loaded ?? 0, e.total ?? f.size);
  });
  req.onLoad.listen((_) {
    if (done.isCompleted) return;
    final text = req.responseText ?? '';
    if (req.status == 200) {
      try {
        final d = jsonDecode(text);
        if (d is Map) {
          done.complete(Map<String, dynamic>.from(d));
        } else {
          done.completeError(StateError('bad response'));
        }
      } catch (e) {
        done.completeError(e);
      }
      return;
    }
    var msg = 'HTTP ${req.status}';
    try {
      final d = jsonDecode(text);
      if (d is Map && d['detail'] != null) msg = '${d['detail']}';
    } catch (_) {}
    done.completeError(Exception(msg));
  });
  req.onError.listen((_) {
    if (!done.isCompleted) done.completeError(Exception('network error'));
  });
  req.onTimeout.listen((_) {
    if (!done.isCompleted) {
      done.completeError(TimeoutException('upload timed out'));
    }
  });
  req.send(form);
  return done.future;
}

/// 网页端不分片：浏览器能直接从磁盘流式发，整包反而更简单。
/// 管理器看到这里抛错就走原来的整传路径，队列也不落盘（刷新页面就没了）。
typedef UploadCancel = CancelToken;

Future<Map<String, dynamic>> postChunkRange(
  String url,
  Map<String, String> headers,
  String path,
  int start,
  int end, {
  UploadProgress? onProgress,
  UploadCancel? cancel,
}) async {
  throw UnsupportedError('web 不分片');
}
