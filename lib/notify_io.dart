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
      // 专用小图标（drawable/ic_notify.xml，单色铃铛）。
      // 之前用的是 @mipmap/ic_launcher：那是自适应图标，插件文档明说
      // release 里可能被剥掉，剥掉之后 initialize 直接失败，每条通知都
      // 静默丢掉——表面上看就是「消息收到了，通知栏什么都没有」。
      android: AndroidInitializationSettings('ic_notify'),
      // iOS 走这条：弹窗、角标、声音都在首次 init 时一次问完，
      // 之后 ask() 只是复查，不会二次弹系统对话框。
      iOS: DarwinInitializationSettings(),
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
    final ios = _p
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      return await ios.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }
    final a = _p
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (a == null) return false;
    return await a.requestNotificationsPermission() ?? false;
  }

  /// 系统设置里关掉了就是 false，用来在设置页给个提示。
  static Future<bool> granted() async {
    final ios = _p
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      final st = await ios.checkPermissions();
      return st?.isEnabled ?? false;
    }
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

  /// 上一次 show 失败的原因。空表示没失败过。
  /// 通知弹不出来时，系统往往是静默吞掉，只能把异常留在这里给人看。
  static String? lastError;

  static Future<String?> show({
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
      } catch (e) {
        lastError = 'init: $e';
        return lastError;
      }
    }
    if (!_ready) {
      lastError = 'init 返回 false';
      return lastError;
    }
    final details = AndroidNotificationDetails(
      _channelId,
      '消息',
      channelDescription: '私信与站内消息提醒',
      importance: Importance.high,
      priority: Priority.high,
      icon: 'ic_notify',
      // 长内容展开能看全，不截成一行。
      styleInformation: BigTextStyleInformation(body),
    );
    try {
      await _p.show(
        id: id,
        title: title,
        body: body,
        payload: payload,
        notificationDetails: NotificationDetails(
          android: details,
          iOS: const DarwinNotificationDetails(),
        ),
      );
      lastError = null;
      return null;
    } catch (e) {
      lastError = '$e';
      return lastError;
    }
  }

  /// 自检：把系统那边看到的状态汇总成一行一行，设置页里直接显示。
  /// 弹不出来的原因多半在这里——权限、渠道重要级别、插件有没有起来。
  static Future<List<String>> diagnose() async {
    final out = <String>[];
    out.add('插件就绪: ${_ready ? '是' : '否'}');
    if (lastError != null) out.add('上次失败: $lastError');
    final ios = _p
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      try {
        final st = await ios.checkPermissions();
        out.add('系统允许通知: ${st?.isEnabled ?? false}');
      } catch (e) {
        out.add('系统允许通知: 查询失败 $e');
      }
      return out;
    }
    final a = _p
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (a == null) {
      out.add('平台实现: 取不到');
      return out;
    }
    try {
      out.add('系统允许通知: ${await a.areNotificationsEnabled() ?? false}');
    } catch (e) {
      out.add('系统允许通知: 查询失败 $e');
    }
    try {
      final ch = await a.getNotificationChannels();
      if (ch == null || ch.isEmpty) {
        out.add('渠道: 一个都没有');
      } else {
        out.add(
          '渠道: ${ch.map((c) => '${c.id}/${c.importance.name}').join(' ')}',
        );
      }
    } catch (e) {
      out.add('渠道: 查询失败 $e');
    }
    return out;
  }

  static Future<void> cancel(int id) async {
    if (!_ready) return;
    await _p.cancel(id: id);
  }
}
