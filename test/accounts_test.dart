import 'package:flutter_test/flutter_test.dart';
import 'package:shijianxian_app/accounts.dart';

void main() {
  test('Account 能从 user 建出来并原样存回 json', () {
    final a = Account.fromUser('tok', {
      'id': 7,
      'uid': 3,
      'name': 'admin',
      'nickname': '阿尔',
      'handle': 'a1',
      'avatar': '/img/a.jpg',
    });
    expect(a.id, 7);
    expect(a.uid, '3');
    expect(a.nickname, '阿尔');

    final b = Account.fromJson(a.toJson());
    expect(b.token, 'tok');
    expect(b.name, 'admin');
    expect(b.handle, 'a1');
    expect(b.avatar, '/img/a.jpg');
    expect(b.sameAccount(a), isTrue);
  });

  test('缺字段不炸，昵称退回登录名', () {
    final a = Account.fromUser('t', {'id': 1, 'name': 'kaluto'});
    expect(a.nickname, 'kaluto');
    expect(a.avatar, '');
    expect(a.id, 1);
  });

  test('同 id 不同 token 认作同一个账号', () {
    final a = Account.fromUser('old', {'id': 9, 'name': 'x'});
    final b = Account.fromUser('new', {'id': 9, 'name': 'x'});
    expect(a.sameAccount(b), isTrue);
    expect(a.token == b.token, isFalse);
  });
}
