/// 构建期配置。
///
/// 全部可以用 --dart-define 覆盖，不需要改代码：
///
///   flutter build apk --release \
///     --dart-define=BRAND=OpenBBS \
///     --dart-define=REPO=https://github.com/you/openbbs \
///     --dart-define=SERVERS=https://bbs.example.com,https://backup.example.com
///
/// SERVERS 逗号分隔：第一个是主通道，第二个是备用（没有就只有一个）。
/// 不给就用出厂默认（时间线的 v6 直连 + v4 中转）——客户端开机就得能看帖，
/// 不能先让人填地址。真要空表，显式传 `--dart-define=SERVERS=`。
class SiteConfig {
  const SiteConfig._();

  /// 站点名。目前是编译期常量，以后服务端下发会覆盖它。
  static const String brand = String.fromEnvironment(
    'BRAND',
    defaultValue: 'OpenBBS',
  );

  /// 关于页里显示的项目地址。空就不显示那一行。
  static const String repo = String.fromEnvironment('REPO', defaultValue: '');

  static const String _serversRaw = String.fromEnvironment(
    'SERVERS',
    defaultValue:
        'https://ipv6bbs.kalutoex.dpdns.org:26016,'
        'https://ipv4bbs.kalutoex.dpdns.org:24016',
  );

  /// 出厂站点的显示名。连上之后以服务端自述为准。
  static const String siteName = String.fromEnvironment(
    'SITE_NAME',
    defaultValue: '时间线',
  );

  /// 出厂预置的服务器列表，顺序即优先级。
  static List<String> get servers => _serversRaw
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  /// 没配就是空字符串。空表只可能出现在自编译、显式清空 SERVERS 的包里，
  /// 那种包才需要人去设置页手填地址。
  static String get defaultServer => servers.isEmpty ? '' : servers.first;
}
