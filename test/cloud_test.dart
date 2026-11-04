import 'package:flutter_test/flutter_test.dart';
import 'package:openbbs/cloud.dart';

void main() {
  test('用量解析：有额度', () {
    final u = CloudUsage.fromJson(const {
      'quota': 1024 * 1024,
      'used': 512 * 1024,
      'count': 3,
      'trash': 1024,
      'trash_count': 1,
    });
    expect(u.unlimited, isFalse);
    expect(u.used, 512 * 1024);
    expect(u.ratio, closeTo(0.5, 1e-9));
    expect(u.left, 512 * 1024);
  });

  test('用量解析：quota 为 null 或 0 都当作不限', () {
    expect(CloudUsage.fromJson(const {'quota': null}).unlimited, isTrue);
    expect(CloudUsage.fromJson(const {'quota': 0}).unlimited, isTrue);
    expect(CloudUsage.fromJson(const {'quota': 0}).ratio, 0);
  });

  test('用量解析：缺字段不炸', () {
    final u = CloudUsage.fromJson(const {});
    expect(u.used, 0);
    expect(u.count, 0);
    expect(u.trashCount, 0);
  });

  test('文件解析：字段齐全', () {
    final f = CloudFile.fromJson(const {
      'id': 7,
      'digest': 'abc',
      'name': 'a.zip',
      'size': 2048,
      'url': '/f/abc',
      'source': 'post',
      'public': true,
      'thread_id': 12,
      'created_at': 1700000000,
      'refs': 2,
    });
    expect(f.id, 7);
    expect(f.name, 'a.zip');
    expect(f.public, isTrue);
    expect(f.threadId, 12);
    expect(f.refs, 2);
    expect(f.expiresIn, isNull);
    expect(f.sizeText, '2 KB');
  });

  test('文件解析：回收站里的带倒计时', () {
    final f = CloudFile.fromJson(const {
      'id': 1,
      'name': 'b.bin',
      'size': 0,
      'expires_in': 3600,
    });
    expect(f.expiresIn, 3600);
    expect(f.source, 'cloud');
    expect(f.public, isFalse);
  });

  test('文件解析：字段全缺也不抛', () {
    final f = CloudFile.fromJson(const {});
    expect(f.id, 0);
    expect(f.name, '');
    expect(f.threadId, isNull);
  });

  test('大小写法分档', () {
    expect(bytesText(999), '999 B');
    expect(bytesText(2048), '2 KB');
    expect(bytesText(5 * 1024 * 1024), '5.0 MB');
    expect(bytesText(3 * 1024 * 1024 * 1024), '3.00 GB');
  });
}
