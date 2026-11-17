import 'cancel_token.dart';

/// 网页版没有「存到手机里」这回事：浏览器的存储归浏览器管，
/// 清一次数据全没，也没法保证下次打开还在。
///
/// 所以这里只报「不支持」，不为了接口整齐去造一个假的浏览器下载。
bool get mangaDlOk => false;

Never _no() => throw UnsupportedError('网页版不支持离线漫画');

Future<String> mangaDlRoot(String site) async => _no();

Future<String?> mangaDlReadIndex(String root) async => null;

Future<void> mangaDlWriteIndex(String root, String body) async => _no();

Future<void> mangaDlQuarantineIndex(String root) async {}

Future<bool> mangaDlExists(String path) async => false;

Future<int> mangaDlSize(String path) async => 0;

Future<void> mangaDlRemoveTree(String path) async {}

Future<void> mangaDlMove(String from, String to) async {}

Future<int> mangaDlDeleteFile(String path) async => 0;

Future<int> mangaDlFreeBytes() async => -1;

Future<int> mangaDlFetchChapter({
  required String destDir,
  required List<String> urls,
  required List<String> names,
  required CancelToken cancel,
  required void Function(int done, int total) onPage,
}) async => _no();
