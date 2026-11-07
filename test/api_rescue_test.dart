import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openbbs/api.dart';

/// 冷启动救援：首轮两条入口都没连上，probe 探到一条通了之后，
/// 必须把出口换过去再重发，而不是还打原来那条死路。
void main() {
  test('救援探到活路：换过去重发，不白探', () async {
    // 一条确定没人听的地址，当本轮失败的那条。
    final t = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final dead = 'http://127.0.0.1:${t.port}';
    await t.close(force: true);

    var hits = 0;
    final live = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    live.listen((req) async {
      hits++;
      if (hits == 1) {
        // 第一次：不回包直接掐断，模拟系统网络栈还没就绪。
        final s = await req.response.detachSocket(writeHeaders: false);
        s.destroy();
        return;
      }
      req.response.headers.contentType = ContentType.json;
      req.response.write('{"items":[]}');
      await req.response.close();
    });
    final good = 'http://127.0.0.1:${live.port}';

    Api.setEndpoints([good, dead]);
    Api.base = dead;
    Api.token = 'tok';
    try {
      final d = await Api.get('/feed');
      expect((d as Map)['items'], isEmpty);
      // 首轮 1 次（失败）+ probe 1 次 + 重发 1 次。
      expect(hits, 3);
      expect(Api.base, good, reason: '救援探到的那条要成为新出口');
    } finally {
      Api.token = null;
      await live.close(force: true);
    }
  });
}
