import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openbbs/api.dart';

/// 令牌被服务端废掉时，接口层要通知外面清状态。
///
/// 判据只看一条：**带着令牌**却被告知「请先登录」。登录页密码输错是
/// 「用户名或密码不对」，文案不同，不会误触发。
void main() {
  late HttpServer server;
  late String base;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    server.listen((req) async {
      final path = req.uri.path;
      req.response.headers.contentType = ContentType.json;
      if (path.endsWith('/me')) {
        req.response.statusCode = 401;
        req.response.write(jsonEncode({'detail': Api.needLoginMessage}));
      } else if (path.endsWith('/login')) {
        req.response.statusCode = 401;
        req.response.write(jsonEncode({'detail': '用户名或密码不对'}));
      } else {
        req.response.statusCode = 200;
        req.response.write(jsonEncode({'ok': true}));
      }
      await req.response.close();
    });
  });

  tearDown(() async {
    Api.token = null;
    Api.onUnauthorized = null;
    await server.close(force: true);
  });

  test('带令牌收到 401「请先登录」：回调触发一次', () async {
    Api.setEndpoints([base]);
    Api.base = base;
    Api.token = 'expired-token';
    var hit = 0;
    Api.onUnauthorized = () => hit++;

    await expectLater(Api.get('/me'), throwsA(isA<ApiException>()));
    expect(hit, 1);

    // 回调里会清令牌，之后同一个请求不该再触发第二遍。
    Api.token = null;
    await expectLater(Api.get('/me'), throwsA(isA<ApiException>()));
    expect(hit, 1);
  });

  test('没带令牌的 401 不触发（登录页密码输错）', () async {
    Api.setEndpoints([base]);
    Api.base = base;
    Api.token = null;
    var hit = 0;
    Api.onUnauthorized = () => hit++;

    await expectLater(
      Api.postAt([base], '/login', const {'u': 'x', 'p': 'y'}),
      throwsA(isA<ApiException>()),
    );
    expect(hit, 0);
  });

  test('带令牌登录失败也不触发：文案不是「请先登录」', () async {
    Api.setEndpoints([base]);
    Api.base = base;
    Api.token = 'some-token';
    var hit = 0;
    Api.onUnauthorized = () => hit++;

    await expectLater(
      Api.postAt([base], '/login', const {'u': 'x', 'p': 'y'}),
      throwsA(isA<ApiException>()),
    );
    expect(hit, 0);
  });
}
