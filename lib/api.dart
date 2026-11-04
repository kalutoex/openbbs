import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import 'disk_cache.dart';
import 'site_config.dart';
import 'site_meta.dart';
import 'sites.dart';

import '../l10n/l10n.dart';
/// 服务端返回的错误，直接拿去显示。
///
/// [code] 只在「客户端自己造的错误」上有值：那种 message 是写死的中文，
/// 得让界面按当前语言翻译，所以走 ARB（见 l10n/error_text.dart）。
/// 服务端下发的错误 message 是原文，code 为 null，照旧直接显示。
class ApiException implements Exception {
  final String message;
  final int? status;
  final String? code;

  /// 给占位符用的附加内容，比如上传失败时的底层异常原文。
  final String? detail;

  ApiException(this.message, {this.status, this.code, this.detail});
  @override
  String toString() => message;
}

/// 一个极薄的 JSON 客户端。base 和 token 都是可变的，站点页会改。
class Api {
  /// 出厂默认地址。
  ///
  /// 网页版跑在自己的域名上，接口同源，直接拿当前页面的 origin。
  /// 原生版来自构建参数 SERVERS；一个都没配就留空，首次启动进设置页。
  static String get defaultBase =>
      kIsWeb ? Uri.base.origin : SiteConfig.defaultServer;

  /// 当前出口，形如 http://1.2.3.4:8080，不带结尾斜杠。
  static String base = '';

  /// 当前站点的全部入口，v6 在前。换站时整组换掉。
  static List<String> endpoints = const [];

  static String? token;

  static bool get configured => base.isNotEmpty;

  /// 上次连通的地址。切站和冷启动先用它，省一轮探路。
  static String lastGood = '';

  /// 通道被换掉时通知外面（存盘、刷新界面），由 store 挂上去。
  static void Function(String base)? onChannelChanged;

  /// 服务端回「账号已被封禁」时通知外面切封禁页。
  static void Function()? onBanned;

  /// 封禁文案是服务端写死的，客户端按它认。
  static const bannedMessage = '账号已被封禁';

  /// 换一组入口。重复地址去掉，顺序保持调用方给的（已 v6 优先）。
  static void setEndpoints(List<String> urls, {String? preferred}) {
    final out = <String>[];
    for (final u in urls) {
      final v = u.trim().replaceAll(RegExp(r'/+$'), '');
      if (v.isNotEmpty && !out.contains(v)) out.add(v);
    }
    endpoints = out;
    final p = (preferred ?? '').trim();
    if (p.isNotEmpty && out.contains(p)) {
      base = p;
    }
  }

  /// 逐条探一遍这座站的入口，每条都真发一次请求，回 200 才算通。
  ///
  /// 串行，不并发——两条都通时必须稳定落在前面那条（v6）。
  /// 超时给得宽：v6 直连 3 秒，其余走公网/中转，10 秒都算正常。
  /// [mark] 为假时只探不记，站点管理页给别的站探路用它。
  static Future<String?> probeAt(List<String> urls, {bool mark = true}) async {
    for (final c in urls) {
      if (c.isEmpty) continue;
      final ms = looksV6(c) ? 3000 : 10000;
      try {
        final r = await http
            .get(Uri.parse('$c/api/feed'))
            .timeout(Duration(milliseconds: ms));
        if (r.statusCode == 200) {
          if (mark) lastGood = c;
          return c;
        }
      } catch (_) {}
    }
    return null;
  }

  /// 探当前站点。
  static Future<String?> probe() => probeAt(endpoints);

  /// 逐条入口各探一次，回 `{地址: 通不通}`。
  ///
  /// 并发跑，站点管理页要一眼看出 v6 和 v4 各自的结果；
  /// 不写 lastGood——这不是选路，只是报告。
  static Future<Map<String, bool>> probeReport(List<String> urls) async {
    final out = <String, bool>{};
    await Future.wait(
      urls.where((u) => u.isNotEmpty).map((c) async {
        final ms = looksV6(c) ? 3000 : 10000;
        try {
          final r = await http
              .get(Uri.parse('$c/api/feed'))
              .timeout(Duration(milliseconds: ms));
          out[c] = r.statusCode == 200;
        } catch (_) {
          out[c] = false;
        }
      }),
    );
    return out;
  }

  /// 测速：每条入口真发一次请求，回 `{地址: 毫秒}`；不通的入口不会出现在结果里。
  ///
  /// 和 [probeReport] 的区别是这里要的是耗时，所以不并发——同一条路上排队发，
  /// 数字才有比较的意义。超时口径跟探路一致。
  static Future<Map<String, int>> speedTest(List<String> urls) async {
    final out = <String, int>{};
    for (final c in urls) {
      if (c.isEmpty) continue;
      final ms = looksV6(c) ? 3000 : 10000;
      final sw = Stopwatch()..start();
      try {
        final r = await http
            .get(Uri.parse('$c/api/feed'))
            .timeout(Duration(milliseconds: ms));
        if (r.statusCode == 200) out[c] = sw.elapsedMilliseconds;
      } catch (_) {
        // 不通就是没结果，界面按「✗」显示
      }
    }
    return out;
  }

  /// 站点自述。启动时读一次，界面拿它判断协议版本和能力位。
  ///
  /// 先读 `/.well-known/bbs.json`（客户端认站的标准入口，一圈就能拿到），
  /// 读不到再退回 `/api/meta`（老站只有这个）。两次都失败就静默返回 null，
  /// 不能让「读不到元信息」把启动搞挂。
  static Future<SiteMeta?> loadMeta({String? at}) async {
    final b = (at ?? base).trim();
    if (b.isEmpty) return null;
    for (final path in const ['/.well-known/bbs.json', '/api/meta']) {
      try {
        final r = await http
            .get(Uri.parse('$b$path'))
            .timeout(const Duration(seconds: 6));
        if (r.statusCode != 200) continue;
        final m = SiteMeta.fromBody(utf8.decode(r.bodyBytes));
        if (m != null) return m;
      } catch (_) {}
    }
    return null;
  }

  /// 当前出口连不上，就按 endpoints 顺序换下一条再试一次。
  ///
  /// 用户切网络（家里 WiFi → 校园网 → 流量）时，缓存里的地址不一定还对，
  /// 靠这个自己换过去，不用人去站点页点。换通了就把 base 定在新的那条上。
  /// 服务器真回了错误（ApiException）不换——那不是路的问题。
  static Future<T> _withFailover<T>(Future<T> Function() run) async {
    try {
      return await run();
    } catch (e) {
      if (e is ApiException) rethrow;
      final prev = base;
      for (final other in endpoints) {
        if (other == prev) continue;
        base = other;
        try {
          final r = await run();
          lastGood = other;
          onChannelChanged?.call(other);
          return r;
        } on ApiException {
          // 这条路上服务器答了话，问题不在路，回原路重抛。
          base = prev;
          rethrow;
        } catch (_) {
          // 继续下一条
        }
      }
      base = prev;
      rethrow;
    }
  }

  /// 对着指定的站点发 POST，不碰当前出口。
  ///
  /// 登录、注册、找回密码都走这里：这些只在登录站做，站内按入口顺序回落。
  static Future<dynamic> postAt(
    List<String> urls,
    String path,
    Map<String, dynamic> body,
  ) async {
    Object? last;
    for (final b in urls) {
      if (b.isEmpty) continue;
      try {
        final r = await http
            .post(
              _uriAt(b, path),
              headers: {
                'Content-Type': 'application/json',
                if (token != null && token!.isNotEmpty)
                  'Authorization': 'Bearer $token',
              },
              body: jsonEncode(body),
            )
            .timeout(const Duration(seconds: 15));
        return _decode(r);
      } on ApiException {
        rethrow; // 服务端答了话，别换入口重试
      } catch (e) {
        last = e;
      }
    }
    if (last is ApiException) throw last;
    throw ApiException(
      Lc.current.connectFailed('${last ?? ''}'),
      code: 'connectFailed',
      detail: '$last',
    );
  }



  /// 对着指定的站点发 GET，不碰当前出口。
  ///
  /// 站点管理页拉主站目录用它：目录属于登录站，跟当前在看哪座站无关。
  static Future<dynamic> getAt(List<String> urls, String path) async {
    Object? last;
    for (final b in urls) {
      if (b.isEmpty) continue;
      try {
        final r = await http
            .get(_uriAt(b, path), headers: _headers)
            .timeout(const Duration(seconds: 15));
        return _decode(r);
      } on ApiException {
        rethrow; // 服务端答了话，别换入口重试
      } catch (e) {
        last = e;
      }
    }
    throw ApiException(
      Lc.current.connectFailed('${last ?? ''}'),
      code: 'connectFailed',
      detail: '$last',
    );
  }

  static String img(String path) {
    if (path.isEmpty) return path;
    if (path.startsWith('http')) return path;
    final b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    return '$b$path';
  }

  /// 缩略图地址。一屏里几张图，没必要每张都拉整图，服务端按宽度切好存着。
  /// 只有网页版用：App 端有磁盘缓存，整图拉一次就长期留着，没必要为省流量牺牲清晰度。
  /// 拿不到本地路径（远端站点的图、空路径）也退回原图地址。
  static String thumb(String path, int width) {
    if (!kIsWeb) return img(path);
    if (path.startsWith('/img/')) {
      return img('/img/t/$width/${path.substring(5)}');
    }
    return img(path);
  }

  /// 上传一张图，返回服务端的相对路径。
  static Future<String> uploadImage(
    Uint8List bytes, {
    String name = 'a.jpg',
  }) async {
    if (!configured) throw ApiException(Lc.current.errNotConfigured, code: 'notConfigured');
    final body = jsonEncode({'name': name, 'data': base64Encode(bytes)});
    try {
      final r = await _withFailover(() => http
          .post(_uri('/upload'), headers: _headers, body: body)
          .timeout(const Duration(seconds: 60)));
      final d = _decode(r);
      final url = (d is Map ? d['url'] : null) as String?;
      if (url == null || url.isEmpty) throw ApiException('upload returned no url', code: 'uploadNoUrl');
      return url;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(Lc.current.uploadFailedWith('${e}'), code: 'uploadFailed', detail: '$e');
    }
  }

  static Uri _uri(String path, [Map<String, String>? query]) =>
      _uriAt(base, path, query);

  static Uri _uriAt(
    String baseUrl,
    String path, [
    Map<String, String>? query,
  ]) {
    final b = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final uri = Uri.parse('$b/api$path');
    return query == null || query.isEmpty
        ? uri
        : uri.replace(queryParameters: query);
  }

  static Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (token != null && token!.isNotEmpty) 'Authorization': 'Bearer $token',
  };

  static dynamic _decode(http.Response r) {
    dynamic body;
    try {
      body = r.body.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes));
    } catch (_) {
      throw ApiException(
        'server returned something unparseable (${r.statusCode})',
        code: 'badResponse',
        status: r.statusCode,
      );
    }
    if (r.statusCode >= 400) {
      final d = body is Map ? body['detail'] : null;
      // 封号：接口层统一回 403 + 固定文案，客户端据此切全局封禁页。
      if (r.statusCode == 403 &&
          d is String &&
          d.contains(bannedMessage)) {
        onBanned?.call();
      }
      // 服务端给了 detail 就用它（原文，服务端说了算）；
      // 没给才是客户端自己兜的这句，得能翻译。
      if (d is String && d.isNotEmpty) {
        throw ApiException(d, status: r.statusCode);
      }
      throw ApiException(
        'request failed (${r.statusCode})',
        status: r.statusCode,
        code: 'requestFailed',
      );
    }
    return body;
  }

  /// 上一次 get 是不是从本地缓存里捞出来的（调用方据此提示「离线」）。
  static bool lastFromCache = false;

  static String _cacheKey(String path, Map<String, String>? query) {
    final q = (query ?? const <String, String>{});
    final ks = q.keys.toList()..sort();
    return '$base$path?${ks.map((k) => '$k=${q[k]}').join('&')}';
  }

  /// [cache] 为真时：成功就顺手存一份，连不上就拿上次的顶。
  static Future<dynamic> get(
    String path, {
    Map<String, String>? query,
    bool cache = false,
  }) async {
    if (!configured) throw ApiException(Lc.current.errNotConfigured);
    final key = cache ? _cacheKey(path, query) : '';
    try {
      final r = await _withFailover(() => http
          .get(_uri(path, query), headers: _headers)
          .timeout(const Duration(seconds: 15)));
      final d = _decode(r);
      lastFromCache = false;
      if (cache) unawaited(DiskCache.write(key, d));
      return d;
    } on ApiException {
      rethrow;
    } catch (e) {
      if (cache) {
        final old = await DiskCache.read(key);
        if (old != null) {
          lastFromCache = true;
          return old;
        }
      }
      throw ApiException(Lc.current.connectFailed('${e}'), code: 'connectFailed', detail: '$e');
    }
  }

  static Future<dynamic> post(String path, Map<String, dynamic> body) async {
    if (!configured) throw ApiException(Lc.current.errNotConfigured);
    try {
      final r = await _withFailover(() => http
          .post(_uri(path), headers: _headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 15)));
      return _decode(r);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(Lc.current.connectFailed('${e}'), code: 'connectFailed', detail: '$e');
    }
  }

  static Future<dynamic> delete(String path) async {
    if (!configured) throw ApiException(Lc.current.errNotConfigured);
    try {
      final r = await _withFailover(() => http
          .delete(_uri(path), headers: _headers)
          .timeout(const Duration(seconds: 15)));
      return _decode(r);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(Lc.current.connectFailed('${e}'), code: 'connectFailed', detail: '$e');
    }
  }

  static Future<dynamic> patch(String path, Map<String, dynamic> body) async {
    if (!configured) throw ApiException(Lc.current.errNotConfigured);
    try {
      final r = await _withFailover(() => http
          .patch(_uri(path), headers: _headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 15)));
      return _decode(r);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(Lc.current.connectFailed('${e}'), code: 'connectFailed', detail: '$e');
    }
  }
}
