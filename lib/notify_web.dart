/// 网页端不做系统通知：浏览器通知要另走一套权限和 Service Worker，
/// 现在打开着页面时角标已经够用。接口对齐 notify_io.dart，全是空实现。
class SysNotify {
  static const idDm = 1001;
  static const idNotice = 1002;
  static const idTest = 1003;

  static bool get ready => false;

  static Future<bool> init(void Function(String payload) onTap) async => false;
  static Future<bool> ask() async => false;
  static Future<bool> granted() async => false;

  static String? lastError;

  static Future<String?> show({
    required int id,
    required String title,
    required String body,
    required String payload,
  }) async => null;

  static Future<List<String>> diagnose() async => ['网页端不弹系统通知'];

  static Future<void> cancel(int id) async {}
}
