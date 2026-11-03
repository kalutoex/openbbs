import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'api.dart';

/// 服务器上放着的安装包信息。
class AppRelease {
  final String version;
  final int build;
  final int size;
  final String url;
  final String notes;

  /// stable 或 beta。服务端决定，客户端只用来显示。
  final String channel;

  const AppRelease({
    required this.version,
    required this.build,
    required this.size,
    required this.url,
    required this.notes,
    required this.channel,
  });

  factory AppRelease.fromJson(Map<String, dynamic> j) => AppRelease(
    version: '${j['version'] ?? ''}',
    build: (j['build'] ?? 0) as int,
    size: (j['size'] ?? 0) as int,
    url: '${j['url'] ?? ''}',
    notes: '${j['notes'] ?? ''}',
    channel: '${j['channel'] ?? 'stable'}',
  );

  String get sizeText => size >= 1024 * 1024
      ? '${(size / 1024 / 1024).toStringAsFixed(1)} MB'
      : '${(size / 1024).toStringAsFixed(0)} KB';
}

/// 问服务器要最新版本。没有安装包时抛 ApiException。
///
/// [beta] 是内测通道，服务端只对管理员生效，普通用户传了也会被按稳定版处理。
Future<AppRelease> fetchLatest({bool beta = false}) async {
  final d = await Api.get(
    '/app/latest',
    query: beta ? const {'channel': 'beta'} : null,
  );
  return AppRelease.fromJson(d);
}

/// 下到临时目录，返回文件。
Future<File> downloadApk(
  AppRelease r,
  void Function(double progress) onProgress,
) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/openbbs-${r.version}.apk');
  if (await file.exists()) await file.delete();

  final client = http.Client();
  try {
    final res = await client.send(
      http.Request('GET', Uri.parse('${Api.base}${r.url}')),
    );
    if (res.statusCode != 200) {
      throw ApiException(
        'download failed (${res.statusCode})',
        code: 'downloadFailed',
        status: res.statusCode,
      );
    }
    final total = res.contentLength ?? r.size;
    final sink = file.openWrite();
    var got = 0;
    await for (final chunk in res.stream) {
      sink.add(chunk);
      got += chunk.length;
      if (total > 0) onProgress((got / total).clamp(0, 1));
    }
    await sink.close();
  } finally {
    client.close();
  }
  return file;
}
