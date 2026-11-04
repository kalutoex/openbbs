import 'package:url_launcher/url_launcher.dart';

/// 网页版点了附件就让浏览器自己下：服务端给的是 attachment，
/// 不会在本站页面里渲染。
Future<void> openRemoteFile(String url, String name,
    {void Function(double)? onProgress}) async {
  final uri = Uri.parse(url);
  await launchUrl(uri, webOnlyWindowName: '_blank');
}
