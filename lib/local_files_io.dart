import 'dart:io';

import 'download_index.dart';

/// 安卓走 MediaStore 存下来时没有真实路径，只给了 `Download/OpenBBS/名字`。
/// 这个相对位置是固定的，拼回来就能读、能列、能定位。
String? publicDownloadPath(String display) {
  const prefix = 'Download/OpenBBS/';
  if (!display.startsWith(prefix)) return null;
  final name = display.substring(prefix.length);
  if (name.isEmpty) return null;
  return '/storage/emulated/0/$prefix$name';
}

/// 文件实际在哪儿。还在就返回可用路径，不在返回 null。
Future<String?> localFileOf(LocalDownload d) async {
  final cands = <String>[
    if (d.path != null && d.path!.isNotEmpty) d.path!,
    ?publicDownloadPath(d.display),
  ];
  for (final p in cands) {
    try {
      if (await File(p).exists()) return p;
    } catch (_) {
      // 没权限或坏了，换下一条
    }
  }
  return null;
}

/// 默认落点里现在有些什么。老版本下载没留记录，扫一遍补上。
Future<List<LocalDownload>> scanDownloadDir() async {
  if (!Platform.isAndroid) return const [];
  final dir = Directory('/storage/emulated/0/Download/OpenBBS');
  if (!await dir.exists()) return const [];
  try {
    final out = <LocalDownload>[];
    await for (final e in dir.list(followLinks: false)) {
      if (e is! File) continue;
      final name = e.path.split('/').last;
      if (name.isEmpty || name.startsWith('.')) continue;
      var size = 0;
      var at = 0;
      try {
        final st = await e.stat();
        size = st.size;
        at = st.modified.millisecondsSinceEpoch ~/ 1000;
      } on FileSystemException {
        continue;
      }
      out.add(
        LocalDownload(
          name: name,
          display: 'Download/OpenBBS/$name',
          path: e.path,
          size: size,
          at: at,
        ),
      );
    }
    return out;
  } catch (_) {
    return const [];
  }
}

Future<int> sizeOfFile(String path) async {
  try {
    return await File(path).length();
  } catch (_) {
    return 0;
  }
}

Future<bool> deleteLocalFile(String path) async {
  try {
    await File(path).delete();
    return true;
  } catch (_) {
    return false;
  }
}
