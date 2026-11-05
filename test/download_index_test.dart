import 'package:flutter_test/flutter_test.dart';
import 'package:openbbs/download_index.dart';
import 'package:openbbs/downloads.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 本机下载记录：云盘靠它认「这个我下过」，「已下载」页靠它列文件。
/// 记错一条的后果是：点已下载的文件又被下一遍，或者列表里凭空多一行。所以单独守一下。
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('记一条，能读回来', () async {
    await rememberLocalDownload(
      const SavedFile(
        display: 'Download/OpenBBS/a.png',
        uri: 'content://x/a',
        path: null,
      ),
      size: 1234,
      cloudId: '7',
    );
    final list = await loadLocalDownloads();
    expect(list, hasLength(1));
    expect(list.first.name, 'a.png');
    expect(list.first.size, 1234);
    expect(list.first.cloudId, '7');
    expect(list.first.uri, 'content://x/a');
  });

  test('同一个落点再记一次，不叠加，排到最前', () async {
    await rememberLocalDownload(const SavedFile(display: 'Download/OpenBBS/a'));
    await rememberLocalDownload(const SavedFile(display: 'Download/OpenBBS/b'));
    await rememberLocalDownload(
      const SavedFile(display: 'Download/OpenBBS/a'),
      size: 9,
    );
    final list = await loadLocalDownloads();
    expect(list, hasLength(2));
    expect(list.first.display, 'Download/OpenBBS/a');
    expect(list.first.size, 9);
  });

  test('记的时候没给 cloudId，读回来是 null', () async {
    await rememberLocalDownload(const SavedFile(display: 'Download/OpenBBS/c'));
    expect((await loadLocalDownloads()).first.cloudId, isNull);
  });

  test('删一条、删一批', () async {
    await rememberLocalDownload(const SavedFile(display: 'Download/OpenBBS/a'));
    await rememberLocalDownload(const SavedFile(display: 'Download/OpenBBS/b'));
    await rememberLocalDownload(const SavedFile(display: 'Download/OpenBBS/c'));
    await forgetLocalDownload('Download/OpenBBS/b');
    expect(
      (await loadLocalDownloads()).map((e) => e.name),
      ['c', 'a'],
    );
    await forgetLocalDownloads(['Download/OpenBBS/a', 'Download/OpenBBS/c']);
    expect(await loadLocalDownloads(), isEmpty);
  });

  test('存档坏了就当没有，不炸', () async {
    SharedPreferences.setMockInitialValues({'local_downloads': '不是 json'});
    expect(await loadLocalDownloads(), isEmpty);
  });
}
