import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openbbs/api.dart';

/// 冷启动救援里的重发拿到 401，不该被吞成「连不上服务器」。
///
/// 单独一个文件：救援有 30 秒节流，和别的救援用例放一起会互相挡住。
void main() {
  test('救援重发收到 401：原样抛出，并触发掉登录回调', () async {
    var hits = 0;
    var expired = 0;
    final live = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    live.listen((req) async {
      hits++;
      if (hits == 1) {
        final s = await req.response.detachSocket(writeHeaders: false);
        s.destroy();
        return;
      }
      if (hits == 3) {
        // 救援重发这一次：令牌废了。
        req.response.statusCode = 401;
        req.response.headers.contentType = ContentType.json;
        req.response.write('{"detail":"请先登录"}');
        await req.response.close();
        return;
      }
      req.response.headers.contentType = ContentType.json;
      req.response.write('{"items":[]}');
      await req.response.close();
    });
    final good = 'http://127.0.0.1:${live.port}';

    Api.setEndpoints([good]);
    Api.base = good;
    Api.token = 'tok';
    Api.onUnauthorized = () => expired++;
    try {
      await expectLater(
        Api.get('/feed'),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)),
      );
      expect(hits, 3, reason: '第 3 次是救援重发');
      expect(expired, 1, reason: '令牌失效要通知外面清登录态');
    } finally {
      Api.token = null;
      Api.onUnauthorized = null;
      await live.close(force: true);
    }
  });
}
