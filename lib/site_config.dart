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
/// 一个都不给也可以，首次启动会进设置页让用户自己填地址。
class SiteConfig {
  const SiteConfig._();

  /// 站点名。目前是编译期常量，以后服务端下发会覆盖它。
  static const String brand =
      String.fromEnvironment('BRAND', defaultValue: 'OpenBBS');

  /// 关于页里显示的项目地址。空就不显示那一行。
  static const String repo = String.fromEnvironment('REPO', defaultValue: '');

  static const String _serversRaw =
      String.fromEnvironment('SERVERS', defaultValue: '');

  /// 出厂预置的服务器列表，顺序即优先级。
  static List<String> get servers => _serversRaw
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  /// 没配就是空字符串，App 会停在设置页。
  static String get defaultServer => servers.isEmpty ? '' : servers.first;
}
