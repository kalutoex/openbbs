/// 网页版没有前台服务这回事，浏览器标签在就接着传，关了就断。
/// 留成空函数，调用点不用分平台。
Future<void> keepAliveStart(String title, String text) async {}

Future<void> keepAliveUpdate(String title, String text) async {}

Future<void> keepAliveStop() async {}
