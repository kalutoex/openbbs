import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openbbs/api.dart';

/// 写请求的幂等号：同一次操作换入口重发要用同一个号，
/// 服务端靠它去重，不会变成发两条帖。两次不同的操作必须换成新号。
void main() {
  test('换入口重发沿用同一个 X-Request-Id', () async {
    final probe = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final dead = 'http://127.0.0.1:${probe.port}';
    await probe.close(force: true);

    final ids = <String?>[];
    final live = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    live.listen((req) async {
      ids.add(req.headers.value('x-request-id'));
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode({'ok': true}));
      await req.response.close();
    });

    Api.setEndpoints([dead, 'http://127.0.0.1:${live.port}']);
    Api.base = dead;
    Api.token = 'tok';
    try {
      await Api.post('/threads', const {'t': 'x'});
      expect(ids.length, 1);
      final id = ids.single;
      expect(id, isNotNull);
      expect(id!.length, greaterThanOrEqualTo(8));
      expect(id, matches(RegExp(r'^[0-9a-zA-Z_-]+$')));

      // 再发一次新请求，号必须换掉——否则服务端会把第二次也当重复吞掉。
      await Api.post('/threads', const {'t': 'y'});
      expect(ids.length, 2);
      expect(ids.last, isNot(id));
    } finally {
      Api.token = null;
      await live.close(force: true);
    }
  });

  test('patch / delete 也带号', () async {
    final seen = <String, String?>{};
    final srv = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    srv.listen((req) async {
      seen[req.method] = req.headers.value('x-request-id');
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode({'ok': true}));
      await req.response.close();
    });

    Api.setEndpoints(['http://127.0.0.1:${srv.port}']);
    Api.base = 'http://127.0.0.1:${srv.port}';
    Api.token = 'tok';
    try {
      await Api.patch('/me', const {'nickname': 'x'});
      await Api.delete('/threads/1');
      expect(seen['PATCH'], isNotNull);
      expect(seen['DELETE'], isNotNull);
      expect(seen['PATCH'], isNot(seen['DELETE']));
    } finally {
      Api.token = null;
      await srv.close(force: true);
    }
  });
}
