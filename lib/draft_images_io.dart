import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// 草稿里的图存成文件，不进 prefs——几张压缩图就能把 XML 撑死。
/// 目录：appSupport/drafts/论坛名/0.bin、1.bin ……
Future<Directory> _dir(String slot) async {
  final base = await getApplicationSupportDirectory();
  return Directory('${base.path}/drafts/${Uri.encodeComponent(slot)}');
}

Future<List<String>> saveDraftImages(String slot, List<Uint8List> imgs) async {
  final d = await _dir(slot);
  if (await d.exists()) await d.delete(recursive: true);
  if (imgs.isEmpty) return const [];
  await d.create(recursive: true);
  final out = <String>[];
  for (var i = 0; i < imgs.length; i++) {
    final f = File('${d.path}/$i.bin');
    await f.writeAsBytes(imgs[i], flush: true);
    out.add(f.path);
  }
  return out;
}

Future<List<Uint8List>> loadDraftImages(String slot) async {
  try {
    final d = await _dir(slot);
    if (!await d.exists()) return const [];
    final files = await d
        .list()
        .where((e) => e is File && e.path.endsWith('.bin'))
        .cast<File>()
        .toList();
    files.sort((a, b) {
      int n(File f) =>
          int.tryParse(f.path.split('/').last.replaceAll('.bin', '')) ?? 0;
      return n(a).compareTo(n(b));
    });
    final out = <Uint8List>[];
    for (final f in files) {
      final b = await f.readAsBytes();
      if (b.isNotEmpty) out.add(b);
    }
    return out;
  } catch (_) {
    return const [];
  }
}

Future<void> clearDraftImages(String slot) async {
  try {
    final d = await _dir(slot);
    if (await d.exists()) await d.delete(recursive: true);
  } catch (_) {
    // 清不掉就算了，下次写会整个覆盖
  }
}
