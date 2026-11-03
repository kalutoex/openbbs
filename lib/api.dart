import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import 'disk_cache.dart';
import 'site_config.dart';
import 'site_meta.dart';

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

/// 服务器选路方式。
enum ServerMode { auto, ipv6, ipv4, manual }

/// 一个极薄的 JSON 客户端。base 和 token 都是可变的，设置页会改。
class Api {
  /// 出厂默认地址。
  ///
  /// 网页版跑在自己的域名上，接口同源，直接拿当前页面的 origin。
  /// 原生版来自构建参数 SERVERS；一个都没配就留空，首次启动进设置页。
  static String get defaultBase =>
      kIsWeb ? Uri.base.origin : SiteConfig.defaultServer;

  /// 主通道 / 备用通道。
  ///
  /// 原来是「IPv6 直连 + IPv4 frp 兜底」写死的两个域名，现在改成构建参数：
  ///   --dart-define=SERVERS=https://主,https://备
  /// 只配一个就只有一个通道，选路那几档自然退化成单通道。
  static String get chIpv6 =>
      SiteConfig.servers.isNotEmpty ? SiteConfig.servers[0] : '';
  static String get chIpv4 =>
      SiteConfig.servers.length > 1 ? SiteConfig.servers[1] : chIpv6;

  /// 当前选路方式。判断都在手机本地做。
  static ServerMode mode = ServerMode.auto;

  /// 上次连通的地址，自动档探测失败时退回这里。
  static String lastGood = '';

  static List<String> get candidates {
    switch (mode) {
      case ServerMode.auto:
        return [chIpv6, chIpv4];
      case ServerMode.ipv6:
        return [chIpv6];
      case ServerMode.ipv4:
        return [chIpv4];
      case ServerMode.manual:
        return [base.isEmpty ? chIpv4 : base];
    }
  }

  /// 手机上逐条探一遍，每条都真发一次请求，回 200 才算通。
  ///
  /// 自动档：先 IPv6，通了就用，不通再试 IPv4。串行，不并发——
  /// 两边都通时必须稳定落在 IPv6 上。
  /// 超时给得宽：IPv6 直连 3 秒（慢就说明没 IPv6）；IPv4 走 frp，
  /// 绕公网一圈，首包 10 秒都算正常，卡太紧会把能用的判成不通。
  static Future<String?> probe() async {
    final list = candidates;
    for (var i = 0; i < list.length; i++) {
      final c = list[i];
      if (c.isEmpty) continue;
      final ms = i == 0 ? 3000 : 10000;
      try {
        final r = await http
            .get(Uri.parse('$c/api/feed'))
            .timeout(Duration(milliseconds: ms));
        if (r.statusCode == 200) {
          lastGood = c;
          return c;
        }
      } catch (_) {}
    }
    return null;
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

  /// 形如 http://1.2.3.4:8080，不带结尾斜杠
  static String base = '';
  static String? token;

  static bool get configured => base.isNotEmpty;

  /// 服务端给的是 /img/xxx 相对路径，拼上 base 才能显示。
  /// 通道被换掉时通知外面（存盘、刷新设置页显示），由 store 挂上去。
  static void Function(String base)? onChannelChanged;

  /// 自动档专用：当前通道连不上，就换另一条再试一次。
  ///
  /// 用户切网络（家里 WiFi → 校园网 → 流量）时，缓存里的地址不一定还对，
  /// 靠这个自己换过去，不用人去设置页点。换通了就把 base 定在新的那条上。
  /// 服务器真回了错误（ApiException）不换——那不是路的问题。
  static Future<T> _withFailover<T>(Future<T> Function() run) async {
    try {
      return await run();
    } catch (e) {
      if (e is ApiException) rethrow;
      if (mode != ServerMode.auto) rethrow;
      final other = base == chIpv4 ? chIpv6 : chIpv4;
      if (other.isEmpty || other == base) rethrow;
      final prev = base;
      base = other;
      try {
        final r = await run();
        lastGood = other;
        onChannelChanged?.call(other);
        return r;
      } catch (_) {
        base = prev;
        rethrow;
      }
    }
  }

  static String img(String path) {
    if (path.isEmpty) return path;
    if (path.startsWith('http')) return path;
    final b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    return '$b$path';
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

  static Uri _uri(String path, [Map<String, String>? query]) {
    final b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
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
