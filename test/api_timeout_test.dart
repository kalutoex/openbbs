import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openbbs/api.dart';

/// 写操作超时：换入口重发，但带同一个幂等号。
///
/// 这条要真等 15 秒（[Api] 的写超时），跑得慢，但它守住的是一段历史：
/// 以前超时不敢重发——超时那条入口的服务端多半已经把请求处理完了，
/// 客户端没等到回程，换条路再发一遍就是两条帖子、两份上传。
///
/// 现在服务端按 X-Request-Id 去重（60 秒内同一个号只执行一次），重发是安全的，
/// 所以这里要验两件事：真的换过去重发了，以及两次带的号必须一样。
void main() {
  test('POST 超时后换到第二条入口，带同一个 X-Request-Id', () async {
    final slowIds = <String?>[];
    final slow = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    slow.listen((req) async {
      slowIds.add(req.headers.value('x-request-id'));
      // 服务端处理完了，只是响应回来得比客户端耐心更久。
      await Future<void>.delayed(const Duration(seconds: 40));
      try {
        req.response.statusCode = 200;
        req.response.write(jsonEncode({'id': 1}));
        await req.response.close();
      } catch (_) {}
    });

    final fastIds = <String?>[];
    final fast = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    fast.listen((req) async {
      fastIds.add(req.headers.value('x-request-id'));
      req.response.statusCode = 200;
      req.response.write(jsonEncode({'id': 2}));
      await req.response.close();
    });

    final a = 'http://127.0.0.1:${slow.port}';
    final b = 'http://127.0.0.1:${fast.port}';
    Api.setEndpoints([a, b]);
    Api.base = a;
    Api.token = 'tok';

    try {
      final d = await Api.post('/threads', const {'t': 'x'});
      expect((d as Map)['id'], 2, reason: '第二次才拿到结果');
      expect(slowIds.length, 1, reason: '请求发出去了');
      expect(fastIds.length, 1, reason: '换到第二条入口重发了一次');
      expect(fastIds.single, isNotNull);
      expect(fastIds.single, slowIds.single, reason: '两次必须是同一个幂等号，服务端才认得出是重发');
      expect(Api.base, b, reason: '换通了就把出口定在新的这条上');
    } finally {
      Api.token = null;
      await slow.close(force: true);
      await fast.close(force: true);
    }
  }, timeout: const Timeout(Duration(seconds: 90)));
}
