import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 系统通知。安卓走本地通知，点一下回到 App 里对应页面。
///
/// 只做「弹一条」这一件事：谁该弹、弹什么内容，由 poller 判断。
class SysNotify {
  static final _p = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static void Function(String payload)? _onTap;

  /// 私有消息和站内消息各占一条通知位，新消息直接替换旧的，
  /// 不在通知栏里堆一列。
  static const idDm = 1001;
  static const idNotice = 1002;
  static const idTest = 1003;

  static Future<bool> init(void Function(String payload) onTap) async {
    _onTap = onTap;
    const settings = InitializationSettings(
      // 小图标用启动图标，安卓会啃成单色剪影，能用就行。
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    // App 是被通知点开的这一种情况，冷启动时补一次跳转。
    final launch = await _p.getNotificationAppLaunchDetails();
    final ok = await _p.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (r) {
        final p = r.payload;
        if (p != null && p.isNotEmpty) _onTap?.call(p);
      },
    );
    _ready = ok ?? false;
    // 渠道先建出来：第一次 show 才建也行，但那样重要级别改了也掰不回来，
    // 而且后台 isolate 里建渠道容易赶上插件还没注册完。
    await _ensureChannel();
    if (_ready && (launch?.didNotificationLaunchApp ?? false)) {
      final p = launch?.notificationResponse?.payload;
      if (p != null && p.isNotEmpty) {
        // 等第一帧之后再跳，否则 Navigator 还没挂上。
        Future.delayed(
          const Duration(milliseconds: 600),
          () => _onTap?.call(p),
        );
      }
    }
    return _ready;
  }

  /// Android 13 起要问，问过就不再弹窗。
  static Future<bool> ask() async {
    final a = _p
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (a == null) return false;
    return await a.requestNotificationsPermission() ?? false;
  }

  /// 系统设置里关掉了就是 false，用来在设置页给个提示。
  static Future<bool> granted() async {
    final a = _p
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (a == null) return false;
    return await a.areNotificationsEnabled() ?? false;
  }

  /// 通知渠道。id 和前台服务用的不是同一个，互不影响。
  static const _channelId = 'messages';

  static Future<void> _ensureChannel() async {
    if (!_ready) return;
    try {
      final a = _p
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await a?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          '消息',
          description: '私信与站内消息提醒',
          importance: Importance.high,
        ),
      );
    } catch (_) {
      // 建不出来也不挡着弹：show 那边还会再建一次
    }
  }

  static bool get ready => _ready;

  static Future<void> show({
    required int id,
    required String title,
    required String body,
    required String payload,
  }) async {
    // 后台 isolate 里可能来不及走 init，这里兜一次，否则一条都弹不出来
    // 而表面上什么错都没有。
    if (!_ready) {
      try {
        await init(_onTap ?? (_) {});
      } catch (_) {
        return;
      }
    }
    if (!_ready) return;
    final details = AndroidNotificationDetails(
      _channelId,
      '消息',
      channelDescription: '私信与站内消息提醒',
      importance: Importance.high,
      priority: Priority.high,
      // 长内容展开能看全，不截成一行。
      styleInformation: BigTextStyleInformation(body),
    );
    await _p.show(
      id: id,
      title: title,
      body: body,
      payload: payload,
      notificationDetails: NotificationDetails(android: details),
    );
  }

  static Future<void> cancel(int id) async {
    if (!_ready) return;
    await _p.cancel(id: id);
  }
}
