import 'dart:typed_data';

/// 网页版没有本地文件目录，草稿只留文字。
Future<List<String>> saveDraftImages(
  String slot,
  List<Uint8List> imgs,
) async => const [];

Future<List<Uint8List>> loadDraftImages(String slot) async => const [];

Future<void> clearDraftImages(String slot) async {}
