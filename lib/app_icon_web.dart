/// 网页版：桌面图标是浏览器的书签图标，应用改不了。
const bool supported = false;

Future<String> currentAppIcon() async => 'mint';

Future<void> setAppIcon(String key) async {
  throw UnsupportedError('网页版换不了图标');
}
