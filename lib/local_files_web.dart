import 'download_index.dart';

/// 网页版没有「本机文件」这回事：下载归浏览器管，我们既读不到也列不出。
String? publicDownloadPath(String display) => null;

Future<String?> localFileOf(LocalDownload d) async => null;

Future<List<LocalDownload>> scanDownloadDir() async => const [];

Future<int> sizeOfFile(String path) async => 0;

Future<bool> deleteLocalFile(String path) async => false;
