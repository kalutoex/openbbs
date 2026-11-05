// 本机保存的站点。
//
// 第 4 段起客户端不是一个地址，而是一张站点表：一行一座站，行里带多个入口
// （`endpoints`）。选路只在这一行内部做：v6 入口优先，连不上按声明顺序回落。
//
// 和服务端清单（`sites.validate()`）共用三条校验：id 去重、缺地址丢弃、
// 版本过高禁入——在 `site_meta.dart` 的 `parseManifest` 里已经做完，
// 这里只管本机合并、去重和排序。
import 'site_config.dart';
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

  /// 本地屏蔽：站点目录里不再显示它，也不把它的帖子推到眼前。
  /// 只在本地生效，不上报服务端——屏蔽是个人口味，不是站务决定。
  bool blocked;

  /// 运行时状态，不落盘：true = 上次探测通了，false = 连不上，null = 还没探。
  bool? reachable;

  /// 运行时状态：逐条入口通不通（站点管理页显示 v6 / v4 各自的结果）。
  final Map<String, bool> epStatus;

  /// 运行时状态：测速结果，地址 → 毫秒。没测过的入口不在里面。
  final Map<String, int> epMs;

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
    this.blocked = false,
    this.reachable,
    this.lastOk,
    Map<String, bool>? epStatus,
    Map<String, int>? epMs,
  }) : epStatus = epStatus ?? <String, bool>{},
       epMs = epMs ?? <String, int>{};

  /// 地址里什么都没有的行没有意义。
  bool get valid => urls.isNotEmpty;

  /// 是不是主站（时间线）。
  ///
  /// 判据只有一条：这一行的入口里有出厂预置的地址。删了主站那一行，
  /// 客户端就没法保证「至少有一座站能发帖」，所以界面拦着不让删。
  bool get isHome {
    for (final u in urls) {
      final h = hostOf(u);
      if (h.isEmpty) continue;
      for (final v in SiteConfig.servers) {
        if (hostOf(v) == h) return true;
      }
    }
    return false;
  }

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
  ///
  /// 入口取并集，不是覆盖：人手里那条连得上的地址必须留着。
  /// 之前这里是直接替换，服务端 base_url 少写个端口（`:26016`），
  /// 客户端就被带着去连 443，看着就是「地址掉了、登录不上」。
  void applyMeta(SiteMeta m, {bool? master}) {
    if (m.id.isNotEmpty) id = m.id;
    if (m.name.trim().isNotEmpty) name = m.name.trim();
    if (m.urls.isNotEmpty) urls = mergeUrls(urls, m.urls);
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
    epStatus: Map<String, bool>.of(epStatus),
    epMs: Map<String, int>.of(epMs),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'urls': urls,
    'api': api,
    'icon': icon,
    'lang': lang,
    'master': master,
    'blocked': blocked,
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
      blocked: j['blocked'] == true,
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
  factory SiteEntry.fromUrl(
    String url, {
    String name = '',
    bool master = false,
  }) {
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

/// 地址里写明的端口；没写就是空字符串（443 / 80 都是「没写」）。
String portOf(String url) {
  if (url.isEmpty) return '';
  final u = Uri.tryParse(normalizeUrl(url));
  if (u == null || !u.hasPort) return '';
  return '${u.port}';
}

/// 入口取并集：先留 [base] 的顺序，再把 [extra] 里没见过的补上。
///
/// 同一台主机、已有那条带端口、新来的这条没带，就不要新的那条——
/// 没写端口就是 443，站往往不在那儿。服务端 `base_url` 漏端口时靠这条兜住。
List<String> mergeUrls(List<String> base, List<String> extra) {
  final out = <String>[];
  for (final u in base) {
    final v = normalizeUrl(u);
    if (v.isNotEmpty && !out.contains(v)) out.add(v);
  }
  for (final u in extra) {
    final v = normalizeUrl(u);
    if (v.isEmpty || out.contains(v)) continue;
    final host = hostOf(v);
    final port = portOf(v);
    if (port.isEmpty &&
        out.any((x) => hostOf(x) == host && portOf(x).isNotEmpty)) {
      continue;
    }
    out.add(v);
  }
  return out;
}

/// 出厂站点。开机就得有，用户不该先填地址再能看帖。
///
/// 入口来自构建参数 SERVERS（默认时间线的 v6 直连 + v4 中转）。
/// `--dart-define=SERVERS=` 显式清空时返回空表。
List<SiteEntry> builtinSites() {
  final urls = <String>[];
  for (final u in SiteConfig.servers) {
    final v = normalizeUrl(u);
    if (v.isNotEmpty && !urls.contains(v)) urls.add(v);
  }
  if (urls.isEmpty) return const [];
  return [SiteEntry(name: SiteConfig.siteName, urls: urls, master: true)];
}

/// 把出厂站点并进本机表。
///
/// 同主机的行当作同一座站（老版本存下来的那条多半就是它）：
/// 入口取并集，缺端口的旧地址剔掉，名字只在空着时补。
List<SiteEntry> ensureBuiltin(List<SiteEntry> existing) {
  final builtins = builtinSites();
  if (builtins.isEmpty) return existing;
  final out = existing.map((s) => s.copy()).toList();
  for (final b in builtins) {
    var hit = out.indexWhere((s) => s.id.isNotEmpty && s.id == b.id);
    if (hit < 0) {
      hit = out.indexWhere(
        (s) => s.urls.any((u) => b.urls.any((v) => hostOf(u) == hostOf(v))),
      );
    }
    if (hit < 0) {
      out.add(b.copy());
      continue;
    }
    final old = out[hit];
    final urls = mergeUrls(b.urls, old.urls);
    out[hit] = SiteEntry(
      id: old.id.isNotEmpty ? old.id : b.id,
      name: old.name.trim().isNotEmpty ? old.name : b.name,
      urls: urls,
      api: old.api > 0 ? old.api : b.api,
      icon: old.icon.isNotEmpty ? old.icon : b.icon,
      lang: old.lang.isNotEmpty ? old.lang : b.lang,
      master: old.master || b.master,
      reachable: old.reachable,
      lastOk: urls.contains(old.lastOk ?? '') ? old.lastOk : null,
      epStatus: Map<String, bool>.of(old.epStatus),
    );
  }
  return _normalizeMasters(out);
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
    final urls = mergeUrls(old.urls, it.urls);
    out[hit] = SiteEntry(
      id: it.id.isNotEmpty ? it.id : old.id,
      name: it.name.trim().isNotEmpty ? it.name.trim() : old.name,
      urls: urls,
      api: it.api > 0 ? it.api : old.api,
      icon: it.icon.isNotEmpty ? it.icon : old.icon,
      lang: it.lang.isNotEmpty ? it.lang : old.lang,
      master: old.master || it.master,
      reachable: old.reachable,
      lastOk: urls.contains(old.lastOk ?? '') ? old.lastOk : null,
      epStatus: Map<String, bool>.of(old.epStatus),
    );
  }
  return _normalizeMasters(out);
}

/// 登录站唯一：一座都没有时第一座顶上，多出来的只留第一个。
List<SiteEntry> _normalizeMasters(List<SiteEntry> out) {
  if (out.isNotEmpty && !out.any((s) => s.master)) out.first.master = true;
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
