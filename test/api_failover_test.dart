import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openbbs/api.dart';

/// 入口切换：路不通要换，写操作超时不许换。
///
/// 超时那条由 test/api_timeout_test.dart 覆盖（它要真等 15 秒，单独跑）；
/// 这里只测快的：连接建不起来时，POST 仍然换到能用的入口。
void main() {
  test('第一条入口连不上：POST 换到第二条，只发一次', () async {
    // 占一个端口再关掉，拿到一个确定没人听的地址。
    final probe = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final dead = 'http://127.0.0.1:${probe.port}';
    await probe.close(force: true);

    var hits = 0;
    final live = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    live.listen((req) async {
      hits++;
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode({'ok': true}));
      await req.response.close();
    });
    final good = 'http://127.0.0.1:${live.port}';

    Api.setEndpoints([dead, good]);
    Api.base = dead;
    Api.token = 'tok';
    try {
      final d = await Api.post('/threads', const {'t': 'x'});
      expect((d as Map)['ok'], isTrue);
      expect(hits, 1);
      // 换通了就把出口定在新的这条上。
      expect(Api.base, good);
    } finally {
      Api.token = null;
      await live.close(force: true);
    }
  });

  test('两条都不通：报连接失败，不吞掉', () async {
    final a = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final pa = a.port;
    await a.close(force: true);
    final b = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final pb = b.port;
    await b.close(force: true);

    Api.setEndpoints(['http://127.0.0.1:$pa', 'http://127.0.0.1:$pb']);
    Api.base = 'http://127.0.0.1:$pa';
    Api.token = null;
    await expectLater(Api.post('/threads', const {}), throwsA(isA<ApiException>()));
  });
}
