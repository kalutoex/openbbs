import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'downloads_common.dart';

/// 下载完到底落在哪，得让用户看得见、找得到。
///
/// 以前是下到应用临时目录再交给系统，那个目录用户翻不到、系统还会清，
/// 所以「下载好了，文件呢」——就是这个问题。
///
/// 现在：
/// - 安卓默认进系统「下载/OpenBBS」（MediaStore，无需权限，任何文件管理器可见）；
///   用户选了目录就用 SAF 那份授权，重启也记得。
/// - 桌面（Windows 等）默认进「下载/OpenBBS」，可以换成任意目录。
/// - 网页版归浏览器管，不走这里（见 downloads_web.dart）。

class DownloadPrefs {
  static const _kDir = 'download_dir';
  static const _kDirLabel = 'download_dir_label';
  static const _kAutoOpen = 'download_auto_open';

  /// 安卓是 content:// 树，桌面是绝对路径。
  static Future<String?> dirId() async =>
      (await SharedPreferences.getInstance()).getString(_kDir);

  static Future<void> setDir(String? id, String? label) async {
    final p = await SharedPreferences.getInstance();
    if (id == null || id.isEmpty) {
      await p.remove(_kDir);
      await p.remove(_kDirLabel);
    } else {
      await p.setString(_kDir, id);
      await p.setString(_kDirLabel, label ?? id);
    }
  }

  /// 下完自动打开。默认开：点下载多半就是想看。
  static Future<bool> autoOpen() async =>
      (await SharedPreferences.getInstance()).getBool(_kAutoOpen) ?? true;

  static Future<void> setAutoOpen(bool v) async =>
      (await SharedPreferences.getInstance()).setBool(_kAutoOpen, v);

  /// 现在会存到哪。没有设置就报默认位置。
  static Future<String> label() async {
    final p = await SharedPreferences.getInstance();
    final saved = p.getString(_kDirLabel);
    if (saved != null && saved.isNotEmpty) return saved;
    if (Platform.isAndroid) return 'Download/OpenBBS';
    final d = await _defaultDesktopDir();
    return d.path;
  }

  static Future<Directory> _defaultDesktopDir() async {
    Directory? base;
    try {
      base = await getDownloadsDirectory();
    } catch (_) {
      base = null;
    }
    base ??= await getApplicationDocumentsDirectory();
    return Directory('${base.path}${Platform.pathSeparator}OpenBBS');
  }

  static Future<String> _targetDir() async {
    final id = await dirId();
    if (id != null && id.isNotEmpty) return id;
    final d = await _defaultDesktopDir();
    if (!await d.exists()) await d.create(recursive: true);
    return d.path;
  }
}

/// 安卓原生：选目录、写文件、打开 content://。
const _chan = MethodChannel('openbbs/downloads');

/// 让用户挑一个下载目录。取消返回 null。
Future<String?> pickDownloadDir() async {
  if (Platform.isAndroid) {
    final r = await _chan.invokeMapMethod<String, dynamic>('pickDir');
    if (r == null) return null;
    await DownloadPrefs.setDir(r['uri'] as String?, r['label'] as String?);
    return r['label'] as String?;
  }
  final dir = await FilePicker.getDirectoryPath(dialogTitle: '选择下载位置');
  if (dir == null || dir.isEmpty) return null;
  await DownloadPrefs.setDir(dir, dir);
  return dir;
}

Future<void> resetDownloadDir() => DownloadPrefs.setDir(null, null);

/// 把临时文件放到用户看得见的地方。同名不覆盖，自动加 (1)。
Future<SavedFile> saveDownloaded(String tmpPath, String name) async {
  final safe = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_');
  if (Platform.isAndroid) {
    final id = await DownloadPrefs.dirId();
    final r = await _chan.invokeMapMethod<String, dynamic>('save', {
      'src': tmpPath,
      'name': safe,
      'mime': mimeOf(safe),
      'dirUri': id,
    });
    if (r == null) throw StateError('保存失败');
    return SavedFile(
      display: (r['display'] as String?) ?? safe,
      uri: r['uri'] as String?,
      path: r['path'] as String?,
    );
  }
  final dir = Directory(await DownloadPrefs._targetDir());
  if (!await dir.exists()) await dir.create(recursive: true);
  final dst = File('${dir.path}${Platform.pathSeparator}${_unique(dir, safe)}');
  await File(tmpPath).copy(dst.path);
  return SavedFile(display: dst.path, path: dst.path);
}

String _unique(Directory dir, String name) {
  if (!File('${dir.path}${Platform.pathSeparator}$name').existsSync())
    return name;
  final dot = name.lastIndexOf('.');
  final stem = dot > 0 ? name.substring(0, dot) : name;
  final ext = dot > 0 ? name.substring(dot) : '';
  var n = 1;
  while (File('${dir.path}${Platform.pathSeparator}$stem ($n)$ext')
      .existsSync()) {
    n++;
  }
  return '$stem ($n)$ext';
}

/// 打开刚存下的那个文件。
Future<void> openSaved(SavedFile f) async {
  if (Platform.isAndroid && f.uri != null && f.uri!.isNotEmpty) {
    final ok = await _chan.invokeMethod<bool>('open', {
      'uri': f.uri,
      'mime': mimeOf(f.display),
    });
    if (ok == true) return;
  }
  if (f.path != null && f.path!.isNotEmpty) {
    final r = await OpenFilex.open(f.path!);
    if (r.type == ResultType.done) return;
    throw StateError('打不开这个文件：${r.message}');
  }
  throw StateError('不知道文件在哪');
}

// ---------------------------------------------------------------- 下载

/// 下载中转到这个目录，存好之后立刻删掉，不留双份空间。
Future<Directory> _tmpDir() async {
  final base = await getTemporaryDirectory();
  final d = Directory('${base.path}${Platform.pathSeparator}downloads');
  if (!await d.exists()) await d.create(recursive: true);
  return d;
}

int _haveLen(String path) {
  final f = File(path);
  return f.existsSync() ? f.lengthSync() : 0;
}

/// 抓着网络这一头，落到临时文件。断过就接着下。
Future<File> fetchToTemp(
  String url,
  String name, {
  void Function(double)? onProgress,
}) async {
  final dir = await _tmpDir();
  final safe = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_');
  final file = File('${dir.path}${Platform.pathSeparator}$safe');
  var have = _haveLen(file.path);

  final client = http.Client();
  try {
    final req = http.Request('GET', Uri.parse(url));
    final tok = Api.token;
    if (tok != null && tok.isNotEmpty) {
      req.headers['Authorization'] = 'Bearer $tok';
    }
    if (have > 0) req.headers['Range'] = 'bytes=$have-';
    final res = await client.send(req);
    final ok = res.statusCode == 200 || res.statusCode == 206;
    if (!ok) {
      throw http.ClientException('下载失败（${res.statusCode}）', Uri.parse(url));
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
  return file;
}

/// 下载 → 落到下载目录 → 删临时文件。返回落到哪了。
Future<SavedFile> downloadToDevice(
  String url,
  String name, {
  void Function(double)? onProgress,
}) async {
  final tmp = await fetchToTemp(url, name, onProgress: onProgress);
  final saved = await saveDownloaded(tmp.path, name);
  try {
    await tmp.delete();
  } catch (_) {
    // 删不掉就留着，下次清缓存一起清
  }
  return saved;
}

// ---------------------------------------------------------------- 临时目录

Future<int> downloadCacheSize() async {
  try {
    final d = await _tmpDir();
    var sum = 0;
    await for (final e in d.list(recursive: true, followLinks: false)) {
      if (e is File) {
        try {
          sum += await e.length();
        } catch (_) {}
      }
    }
    return sum;
  } catch (_) {
    return 0;
  }
}

Future<void> clearDownloadCache() async {
  try {
    final d = await _tmpDir();
    if (await d.exists()) await d.delete(recursive: true);
  } catch (_) {}
}
