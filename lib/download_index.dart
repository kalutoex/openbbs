import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'downloads.dart';

/// 手机上下载过的文件清单。
///
/// 存在本机，跨启动留着。用处有两个：
/// - 云盘列表认出「这个我下载过」，点一下不再重复下，直接带你去找它；
/// - 「已下载」页靠它列出文件，含那些 Safari 式改过名（x (1).png）的。
///
/// 只记位置，不搬文件。文件被用户手动删了，这里会显示「不在了」。
class LocalDownload {
  const LocalDownload({
    required this.name,
    required this.display,
    this.path,
    this.uri,
    this.size = 0,
    this.at = 0,
    this.cloudId,
  });

  /// 落盘时的文件名，可能带 (1)。
  final String name;

  /// 给人看的落点：Download/OpenBBS/x.png 或某个绝对路径。
  final String display;

  /// 真实文件路径。安卓走 MediaStore 时没有，只有 uri。
  final String? path;
  final String? uri;
  final int size;

  /// 下载时间，秒。
  final int at;

  /// 从云盘下的就记着云盘 id，回来点的时候能对上。
  final String? cloudId;

  SavedFile get saved => SavedFile(display: display, uri: uri, path: path);

  Map<String, Object?> toJson() => {
    'name': name,
    'display': display,
    if (path != null) 'path': path,
    if (uri != null) 'uri': uri,
    'size': size,
    'at': at,
    if (cloudId != null) 'cloudId': cloudId,
  };

  static LocalDownload? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    final display = raw['display'];
    if (name is! String || display is! String) return null;
    return LocalDownload(
      name: name,
      display: display,
      path: raw['path'] as String?,
      uri: raw['uri'] as String?,
      size: (raw['size'] as num?)?.toInt() ?? 0,
      at: (raw['at'] as num?)?.toInt() ?? 0,
      cloudId: raw['cloudId'] as String?,
    );
  }
}

const _kKey = 'local_downloads';

/// 留最近这些条，再往前的记录没意义，翻也翻不到。
const _kMax = 500;

Future<List<LocalDownload>> loadLocalDownloads() async {
  final p = await SharedPreferences.getInstance();
  final raw = p.getString(_kKey);
  if (raw == null || raw.isEmpty) return const [];
  try {
    final list = jsonDecode(raw);
    if (list is! List) return const [];
    return [
      for (final e in list)
        if (LocalDownload.fromJson(e) case final d?) d,
    ];
  } catch (_) {
    return const [];
  }
}

Future<void> _save(List<LocalDownload> list) async {
  final p = await SharedPreferences.getInstance();
  await p.setString(_kKey, jsonEncode(list.map((e) => e.toJson()).toList()));
}

/// 记一条。同一个落点只留最新的一条。
Future<void> rememberLocalDownload(
  SavedFile s, {
  int size = 0,
  int? at,
  String? cloudId,
}) async {
  final list = [...await loadLocalDownloads()];
  final name = s.display.split(RegExp(r'[\\/]')).last;
  list.removeWhere((e) => e.display == s.display);
  list.insert(
    0,
    LocalDownload(
      name: name,
      display: s.display,
      path: s.path,
      uri: s.uri,
      size: size,
      at: at ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
      cloudId: cloudId,
    ),
  );
  if (list.length > _kMax) list.removeRange(_kMax, list.length);
  await _save(list);
}

Future<void> forgetLocalDownload(String display) async {
  final list = [...await loadLocalDownloads()]
    ..removeWhere((e) => e.display == display);
  await _save(list);
}

Future<void> forgetLocalDownloads(Iterable<String> displays) async {
  final drop = displays.toSet();
  final list = [...await loadLocalDownloads()]
    ..removeWhere((e) => drop.contains(e.display));
  await _save(list);
}
