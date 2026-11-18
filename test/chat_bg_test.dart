// 聊天背景存不住那次的回归：写和读用的键不一样。
//
// 1.1.9+100179~100181 里，聊天信息页按 threadId 存、聊天页按 peerId 读，
// 设完背景退出去再进来就白了。现在两边都用 ChatBg.keyOf，旧键在读的时候搬过来。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openbbs/chat_bg.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('chat_bg_test');
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<String> makeImage(String name) async {
    final f = File('${tmp.path}/$name');
    await f.writeAsBytes([1, 2, 3]);
    return f.path;
  }

  test('键带自己的 uid，两个账号不互相盖', () {
    expect(ChatBg.keyOf(1, 7), isNot(ChatBg.keyOf(2, 7)));
    expect(ChatBg.keyOf(1, 7), ChatBg.keyOf(1, 7));
  });

  test('存下去读得回来', () async {
    final png = await makeImage('a.jpg');
    final key = ChatBg.keyOf(1, 7);
    SharedPreferences.setMockInitialValues({key: png});

    expect(await ChatBg.pathOf(key), png);
  });

  test('旧键（按 threadId 存的）搬到新键上，只搬一次', () async {
    final png = await makeImage('b.jpg');
    final key = ChatBg.keyOf(1, 7);
    SharedPreferences.setMockInitialValues({'dm_bg_42': png});

    expect(await ChatBg.pathOf(key, legacy: ['dm_bg_42']), png);

    final p = await SharedPreferences.getInstance();
    expect(p.getString(key), png);
    expect(p.getString('dm_bg_42'), isNull);
  });

  test('旧键上的图已经没了，就当没设过，顺手清掉死键', () async {
    final key = ChatBg.keyOf(1, 7);
    SharedPreferences.setMockInitialValues({
      'dm_bg_42': '${tmp.path}/gone.jpg',
    });

    expect(await ChatBg.pathOf(key, legacy: ['dm_bg_42']), isNull);

    final p = await SharedPreferences.getInstance();
    expect(p.getString(key), isNull);
    expect(p.getString('dm_bg_42'), isNull);
  });

  test('清空把新旧键一起删，文件也删', () async {
    final png = await makeImage('c.jpg');
    final key = ChatBg.keyOf(1, 7);
    SharedPreferences.setMockInitialValues({key: png, 'dm_bg_42': png});

    await ChatBg.clear(key, legacy: ['dm_bg_42']);

    final p = await SharedPreferences.getInstance();
    expect(p.getString(key), isNull);
    expect(p.getString('dm_bg_42'), isNull);
    expect(File(png).existsSync(), isFalse);
  });
}
