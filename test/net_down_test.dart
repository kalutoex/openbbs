import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openbbs/api.dart';

/// 断网提示条靠 Api.netDown 这一个旗子：连不上立起来，通了收回去。
void main() {
  test('全都不通时挂旗，通了就收起来', () async {
    final probe = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final dead = 'http://127.0.0.1:${probe.port}';
    await probe.close(force: true);

    Api.setEndpoints([dead]);
    Api.base = dead;
    Api.token = 'tok';
    expect(Api.netDown.value, isFalse);
    try {
      await expectLater(Api.get('/feed'), throwsA(isA<ApiException>()));
      expect(Api.netDown.value, isTrue);

      final live = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      live.listen((req) async {
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({'items': []}));
        await req.response.close();
      });
      final good = 'http://127.0.0.1:${live.port}';
      Api.setEndpoints([good]);
      Api.base = good;
      try {
        await Api.get('/feed');
        expect(Api.netDown.value, isFalse);
      } finally {
        await live.close(force: true);
      }
    } finally {
      Api.token = null;
    }
  });
}
