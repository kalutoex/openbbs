import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openbbs/file_pick.dart';
import 'package:openbbs/store.dart';
import 'package:openbbs/upload_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 上传队列必须认人。
///
/// 队列是全局一份、落在一个 key 里，令牌却是「当前账号」的。
/// 这两件事一旦错位，文件就会用别人的令牌传进别人的云盘——第 2 段那个 P1。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    UploadManager.i.jobs.clear();
  });

  tearDown(() {
    AppState.instance.user = null;
    UploadManager.i.jobs.clear();
  });

  test('落盘时带上所有者', () {
    final f = PickedFile(name: 'a.bin', size: 10, path: '/tmp/a.bin');
    final job = UploadJob(file: f, id: 'u1', owner: 42);
    expect(job.toJson()['owner'], 42);
  });

  test('老队列没有 owner 字段，归到当前账号名下', () async {
    final dir = Directory.systemTemp.createTempSync('up_owner');
    final file = File('${dir.path}${Platform.pathSeparator}a.bin')
      ..writeAsBytesSync(List.filled(4, 1));
    SharedPreferences.setMockInitialValues({
      'cloud_upload_queue':
          '[{"id":"u9","name":"a.bin","size":4,"path":"${file.path}",'
              '"offset":0}]',
    });
    AppState.instance.user = {'id': 7, 'name': 'me'};

    await UploadManager.i.init();

    expect(UploadManager.i.jobs.length, 1);
    expect(UploadManager.i.jobs.first.owner, 7);
    dir.deleteSync(recursive: true);
  });

  test('别人留下来的队列不加载，也不跟着他的令牌跑', () async {
    final dir = Directory.systemTemp.createTempSync('up_owner2');
    final file = File('${dir.path}${Platform.pathSeparator}b.bin')
      ..writeAsBytesSync(List.filled(4, 1));
    SharedPreferences.setMockInitialValues({
      'cloud_upload_queue':
          '[{"id":"u8","name":"b.bin","size":4,"path":"${file.path}",'
              '"offset":0,"owner":3}]',
    });
    AppState.instance.user = {'id': 7, 'name': 'me'};

    await UploadManager.i.init();

    expect(UploadManager.i.jobs, isEmpty);
    dir.deleteSync(recursive: true);
  });

  test('在另一个账号下点重试，这条就归当前账号', () {
    final f = PickedFile(name: 'c.bin', size: 4, path: '/tmp/c.bin');
    final job = UploadJob(file: f, id: 'u7', owner: 3)
      ..state = UploadState.failed;
    AppState.instance.user = {'id': 7, 'name': 'me'};

    UploadManager.i.retry(job);

    expect(job.owner, 7);
    expect(job.state, UploadState.queued);
  });
}
