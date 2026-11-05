// 站点自述（`/meta`、`/.well-known/bbs.json`、主站目录）。
//
// 协议版本用 `api` 整数：客户端只认到 SiteMeta.supportedApi，
// 服务端报得更高就说明有它不认识的东西，标「需更新客户端」，
// 别硬连——字段含义可能已经变了。
import 'dart:convert';

class SiteEndpoint {
  final String url;
  final String note;

  const SiteEndpoint(this.url, this.note);

  static SiteEndpoint? parse(Object? raw) {
    if (raw is Map) {
      final url = '${raw['url'] ?? ''}'.trim();
      if (url.isEmpty) return null;
      return SiteEndpoint(url, '${raw['note'] ?? ''}');
    }
    final s = '${raw ?? ''}'.trim();
    return s.isEmpty ? null : SiteEndpoint(s, '');
  }
}

class SiteMeta {
  /// 客户端支持的接口版本。
  ///
  /// 1 → 只有帖子和用户
  /// 2 → 站点自述 / 清单 / 登记
  static const int supportedApi = 2;

  final int schema;
  final int api;
  final String id;
  final String name;
  final String description;
  final String url;
  final String lang;
  final String icon;
  final String contact;
  final bool open;
  final List<String> tags;
  final List<String> capabilities;
  final List<SiteEndpoint> endpoints;

  /// 这座站是不是登录站。老服务端不报，null = 不知道，按本机记录算。
  final bool? master;

  /// 小站指向的主站地址。主站是空字符串。
  final String masterUrl;

  const SiteMeta({
    this.schema = 1,
    this.api = 0,
    this.id = '',
    this.name = '',
    this.description = '',
    this.url = '',
    this.lang = '',
    this.icon = '',
    this.contact = '',
    this.open = true,
    this.tags = const [],
    this.capabilities = const [],
    this.endpoints = const [],
    this.master,
    this.masterUrl = '',
  });

  /// 服务端比这台客户端新。别拿它当老接口用。
  bool get tooNew => api > supportedApi;

  /// 对方有没有某个能力位。老站不报 capabilities，一律当没有。
  bool has(String cap) => capabilities.contains(cap);

  /// 全部可用地址，主地址在前，重复的去掉。
  List<String> get urls {
    final out = <String>[];
    void add(String u) {
      final v = u.trim();
      if (v.isNotEmpty && !out.contains(v)) out.add(v);
    }

    add(url);
    for (final e in endpoints) {
      add(e.url);
    }
    return out;
  }

  static List<String> _strList(Object? raw) {
    if (raw is! List) return const [];
    return raw.map((e) => '$e'.trim()).where((e) => e.isNotEmpty).toList();
  }

  static int _int(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse('${raw ?? ''}') ?? 0;
  }

  /// 单条自述。`/meta` 和 `/.well-known/bbs.json` 的 `sites[i]` 是同一个形状。
  static SiteMeta? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final endpoints = <SiteEndpoint>[];
    for (final e
        in (raw['endpoints'] is List ? raw['endpoints'] as List : const [])) {
      final ep = SiteEndpoint.parse(e);
      if (ep != null) endpoints.add(ep);
    }
    final url = '${raw['url'] ?? raw['base_url'] ?? ''}'.trim();
    final id = '${raw['id'] ?? raw['site_id'] ?? ''}'.trim().toLowerCase();
    // 什么都没有的条目连不上，也没法认，直接当无效。
    if (url.isEmpty && endpoints.isEmpty) return null;
    return SiteMeta(
      schema: _int(raw['schema'] ?? 1),
      api: _int(raw['api']),
      id: id,
      name: '${raw['name'] ?? ''}',
      description: '${raw['description'] ?? ''}',
      url: url,
      lang: '${raw['lang'] ?? ''}',
      icon: '${raw['icon'] ?? ''}',
      contact: '${raw['contact'] ?? ''}',
      open: raw['open'] != false,
      tags: _strList(raw['tags']),
      capabilities: _strList(raw['capabilities']),
      endpoints: endpoints,
      master: raw['master'] is bool ? raw['master'] as bool : null,
      masterUrl: '${raw['master_url'] ?? ''}'.trim().replaceAll(
        RegExp(r'/+$'),
        '',
      ),
    );
  }

  /// 清单导入。三条规则，和 server/app/sites.py 的 validate() 一致：
  /// id 去重、缺地址丢弃、版本过高禁入。
  ///
  /// [dropped] 非空时把每条被丢的 `{id, reason}` 塞进去，界面上好说清。
  static List<SiteMeta> parseManifest(
    Object? raw, {
    int maxApi = supportedApi,
    List<Map<String, String>>? dropped,
  }) {
    if (raw is! Map) {
      dropped?.add({'id': '', 'reason': 'bad_format'});
      return const [];
    }
    final sites = raw['sites'];
    if (sites is! List) {
      dropped?.add({'id': '', 'reason': 'bad_format'});
      return const [];
    }
    final keep = <SiteMeta>[];
    final seen = <String>{};
    for (final it in sites) {
      final m = fromJson(it);
      if (m == null) {
        dropped?.add({'id': '', 'reason': 'no_url'});
        continue;
      }
      if (m.api > maxApi) {
        dropped?.add({'id': m.id, 'reason': 'api_too_new'});
        continue;
      }
      if (m.id.isNotEmpty) {
        if (!seen.add(m.id)) {
          dropped?.add({'id': m.id, 'reason': 'duplicate_id'});
          continue;
        }
      }
      keep.add(m);
    }
    return keep;
  }

  /// 调一次自述接口用。`{"sites":[…]}` 和单条都吃。
  static SiteMeta? fromBody(String body) {
    final raw = jsonDecode(body);
    if (raw is Map && raw['sites'] is List) {
      final list = parseManifest(raw);
      return list.isEmpty ? null : list.first;
    }
    return fromJson(raw);
  }
}
