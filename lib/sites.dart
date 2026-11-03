// 本机保存的站点。
//
// 第 4 段起客户端不是一个地址，而是一张站点表：一行一座站，行里带多个入口
// （`endpoints`）。选路只在这一行内部做：v6 入口优先，连不上按声明顺序回落。
//
// 和服务端清单（`sites.validate()`）共用三条校验：id 去重、缺地址丢弃、
// 版本过高禁入——在 `site_meta.dart` 的 `parseManifest` 里已经做完，
// 这里只管本机合并、去重和排序。
import 'site_meta.dart';

/// 本机的一行站点。
///
/// [id] 是主站分配的 `site_id`，没登记过就是空字符串；空的时候用首个地址当 key。
/// [urls] 是 declaim 的入口列表，原顺序保留；实际探测用 [orderedUrls]。
class SiteEntry {
  String id;
  String name;
  List<String> urls;
  int api;
  String icon;
  String lang;

  /// 登录站。注册、登录、找回密码都发到这里，token 全局共用。
  bool master;

  /// 运行时状态，不落盘：true = 上次探测通了，false = 连不上，null = 还没探。
  bool? reachable;

  /// 运行时状态：上次连通的地址，切站时先用它。
  String? lastOk;

  SiteEntry({
    this.id = '',
    this.name = '',
    this.urls = const [],
    this.api = 0,
    this.icon = '',
    this.lang = '',
    this.master = false,
    this.reachable,
    this.lastOk,
  });

  /// 地址里什么都没有的行没有意义。
  bool get valid => urls.isNotEmpty;

  /// 稳定标识：有 id 用 id，没有就用首个地址。
  String get key => id.isNotEmpty ? id : (urls.isEmpty ? name : urls.first);

  String get primary => urls.isEmpty ? '' : urls.first;

  /// 展示名：服务端没给就退回主机名。
  String get display {
    if (name.trim().isNotEmpty) return name.trim();
    final h = hostOf(primary);
    return h.isNotEmpty ? h : primary;
  }

  String get host => hostOf(primary);

  /// v6 入口在前，其余保持原顺序。
  ///
  /// 只认三种「像 v6」的写法：IPv6 字面量、`ipv6` 开头的域名（ipv6bbs.xxx）、
  /// 带 `-v6` 的域名。别的域名不猜，按服务端给的顺序走。
  List<String> get orderedUrls => orderV6First(urls);

  /// 服务端自述回来后刷新这一行。
  void applyMeta(SiteMeta m, {bool? master}) {
    if (m.id.isNotEmpty) id = m.id;
    if (m.name.trim().isNotEmpty) name = m.name.trim();
    if (m.urls.isNotEmpty) urls = m.urls;
    if (m.api > 0) api = m.api;
    if (m.icon.isNotEmpty) icon = m.icon;
    if (m.lang.isNotEmpty) lang = m.lang;
    if (master != null) this.master = master;
  }

  SiteEntry copy() => SiteEntry(
    id: id,
    name: name,
    urls: List<String>.of(urls),
    api: api,
    icon: icon,
    lang: lang,
    master: master,
    reachable: reachable,
    lastOk: lastOk,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'urls': urls,
    'api': api,
    'icon': icon,
    'lang': lang,
    'master': master,
    'last_ok': lastOk ?? '',
  };

  factory SiteEntry.fromJson(Map<String, dynamic> j) {
    final raw = j['urls'];
    final urls = <String>[];
    if (raw is List) {
      for (final u in raw) {
        final v = '$u'.trim();
        if (v.isNotEmpty && !urls.contains(v)) urls.add(v);
      }
    }
    final last = '${j['last_ok'] ?? ''}'.trim();
    return SiteEntry(
      id: '${j['id'] ?? ''}'.trim().toLowerCase(),
      name: '${j['name'] ?? ''}',
      urls: urls,
      api: j['api'] is num ? (j['api'] as num).toInt() : 0,
      icon: '${j['icon'] ?? ''}',
      lang: '${j['lang'] ?? ''}',
      master: j['master'] == true,
      lastOk: urls.contains(last) ? last : null,
    );
  }

  /// 一行自述变一个站点。没 id 的留着，界面上标「未登记」。
  factory SiteEntry.fromMeta(SiteMeta m, {bool master = false}) => SiteEntry(
    id: m.id,
    name: m.name.trim(),
    urls: m.urls,
    api: m.api,
    icon: m.icon,
    lang: m.lang,
    master: master,
  );

  /// 手动填一个地址：先当单入口站点用，读到 /meta 再补名字和入口。
  factory SiteEntry.fromUrl(String url, {String name = '', bool master = false}) {
    final u = normalizeUrl(url);
    return SiteEntry(
      name: name.trim(),
      urls: u.isEmpty ? const [] : [u],
      master: master,
    );
  }
}

/// `http://1.2.3.4:8080`，去掉结尾斜杠；没写协议按 http 补。
String normalizeUrl(String raw) {
  var u = raw.trim();
  if (u.isEmpty) return '';
  if (!u.startsWith('http://') && !u.startsWith('https://')) u = 'http://$u';
  while (u.endsWith('/')) {
    u = u.substring(0, u.length - 1);
  }
  return u;
}

String hostOf(String url) {
  if (url.isEmpty) return '';
  return Uri.tryParse(normalizeUrl(url))?.host ?? '';
}

/// 看起来是 IPv6 直连的入口。
bool looksV6(String url) {
  final h = hostOf(url).toLowerCase();
  if (h.isEmpty) return false;
  if (h.contains(':')) return true; // IPv6 字面量 [2603:...]
  return h.startsWith('ipv6') || h.contains('-v6.');
}

/// v6 入口提到前面，剩下的保持相对顺序。
List<String> orderV6First(List<String> urls) {
  final v6 = <String>[];
  final rest = <String>[];
  for (final u in urls) {
    (looksV6(u) ? v6 : rest).add(u);
  }
  return [...v6, ...rest];
}

/// 把新读到的站点并进本机表。
///
/// 同 id 的更新原来那一行（位置不动），没 id 的按地址重叠认；
/// 都对不上就追加。返回新表，不修改入参。
List<SiteEntry> mergeSites(List<SiteEntry> existing, List<SiteEntry> incoming) {
  final out = existing.map((s) => s.copy()).toList();
  for (final it in incoming) {
    if (!it.valid) continue;
    var hit = -1;
    if (it.id.isNotEmpty) {
      hit = out.indexWhere((s) => s.id == it.id);
    }
    if (hit < 0) {
      hit = out.indexWhere((s) => s.urls.any(it.urls.contains));
    }
    if (hit < 0) {
      out.add(it.copy());
      continue;
    }
    final old = out[hit];
    final urls = List<String>.of(old.urls);
    for (final u in it.urls) {
      if (!urls.contains(u)) urls.add(u);
    }
    out[hit] = SiteEntry(
      id: it.id.isNotEmpty ? it.id : old.id,
      name: it.name.trim().isNotEmpty ? it.name.trim() : old.name,
      urls: urls,
      api: it.api > 0 ? it.api : old.api,
      icon: it.icon.isNotEmpty ? it.icon : old.icon,
      lang: it.lang.isNotEmpty ? it.lang : old.lang,
      master: old.master || it.master,
      reachable: old.reachable,
      lastOk: old.lastOk,
    );
  }
  // 一座登录站都没有时，第一座顶上，不然登录没处发。
  if (out.isNotEmpty && !out.any((s) => s.master)) out.first.master = true;
  // 同一时间只留一个登录站。
  var seenMaster = false;
  for (final s in out) {
    if (!s.master) continue;
    if (seenMaster) {
      s.master = false;
    } else {
      seenMaster = true;
    }
  }
  return out;
}
