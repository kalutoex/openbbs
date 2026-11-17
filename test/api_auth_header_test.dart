import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openbbs/api.dart';

/// 令牌要真的贴到头上，401 的判定也要认「这一发带没带」。
///
/// 2026-11-17 出过两次事故，都是这里：
/// 一是补丁把插值写成了字面量 `Bearer $tok`，登录后每个请求都 401；
/// 二是冷启动令牌还没读出来就发请求，回包时全局令牌已就位，被误判成令牌被废。
void main() {
  test('请求头带的是真令牌，不是字面量', () async {
    final seen = <String?>[];
    final srv = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    srv.listen((req) async {
      seen.add(req.headers.value('authorization'));
      req.response.headers.contentType = ContentType.json;
      req.response.write('{"ok":true}');
      await req.response.close();
    });
    final base = 'http://127.0.0.1:${srv.port}';

    Api.setEndpoints([base]);
    Api.base = base;
    Api.token = 'tok-abc';
    try {
      await Api.get('/feed');
      await Api.post('/feed', {'x': 1});
      expect(seen, ['Bearer tok-abc', 'Bearer tok-abc']);
    } finally {
      Api.token = null;
      await srv.close(force: true);
    }
  });

  test('空手发出去的请求收到 401：不算令牌被废', () async {
    var expired = 0;
    final answered = Completer<void>();
    final srv = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    srv.listen((req) async {
      // 慢半拍再回：留出「回包前令牌已经加载好」的窗口。
      await Future<void>.delayed(const Duration(milliseconds: 120));
      req.response
        ..statusCode = 401
        ..headers.contentType = ContentType.json
        ..write('{"detail":"请先登录"}');
      await req.response.close();
      if (!answered.isCompleted) answered.complete();
    });
    final base = 'http://127.0.0.1:${srv.port}';

    Api.setEndpoints([base]);
    Api.base = base;
    Api.token = null; // 冷启动：令牌还没读出来
    Api.onUnauthorized = () => expired++;
    try {
      final fut = Api.get('/manga/history?limit=12');
      // 请求在飞的时候令牌到账了——旧逻辑会拿它去判这一发。
      await Future<void>.delayed(const Duration(milliseconds: 40));
      Api.token = 'tok-late';
      await expectLater(
        fut,
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)),
      );
      await answered.future;
      expect(expired, 0, reason: '这一发没带令牌，不能当成令牌被废');
    } finally {
      Api.token = null;
      Api.onUnauthorized = null;
      await srv.close(force: true);
    }
  });
}
