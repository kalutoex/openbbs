import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openbbs/api.dart';

/// 写操作超时：不许换入口重发。
///
/// 这条要真等 15 秒（[Api] 的写超时），跑得慢，但它守住的是一个会真出事
/// 的边界——超时那条入口的服务端多半已经把请求处理完了，客户端没等到回程，
/// 换条路再发一遍就成了两条帖子、两份上传。
///
/// 曾经的行为是照换不误（实测：慢入口收到 1 次、快入口也收到 1 次）。
void main() {
  test('POST 超时后停在原地，不往第二条入口重发', () async {
    var slowHits = 0;
    final slow = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    slow.listen((req) async {
      slowHits++;
      // 服务端处理完了，只是响应回来得比客户端耐心更久。
      await Future<void>.delayed(const Duration(seconds: 40));
      try {
        req.response.statusCode = 200;
        req.response.write(jsonEncode({'id': 1}));
        await req.response.close();
      } catch (_) {}
    });

    var fastHits = 0;
    final fast = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    fast.listen((req) async {
      fastHits++;
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
      await expectLater(Api.post('/threads', const {'t': 'x'}), throwsA(isA<ApiException>()));
      expect(slowHits, 1, reason: '请求发出去了');
      expect(fastHits, 0, reason: '不该换入口重发');
      expect(Api.base, a, reason: '出口不该被改掉');
    } finally {
      Api.token = null;
      await slow.close(force: true);
      await fast.close(force: true);
    }
  }, timeout: const Timeout(Duration(seconds: 90)));
}
