import 'package:flutter_test/flutter_test.dart';
import 'package:openbbs/api.dart';
import 'package:openbbs/update.dart';
import 'package:openbbs/update_prompt.dart';

AppRelease _rel({
  String version = '1.4.0',
  int build = 90,
  int forceBelow = 0,
  int checkHours = 24,
  int remindHours = 24,
  String title = '',
  String message = '',
  String notes = '',
}) => AppRelease(
  version: version,
  build: build,
  size: 3 * 1024 * 1024,
  url: '/apk/stable/app-$version+$build.apk',
  notes: notes,
  channel: 'stable',
  forceBelow: forceBelow,
  checkHours: checkHours,
  remindHours: remindHours,
  title: title,
  message: message,
);

void main() {
  test('旧字段缺失也能读，策略走默认值', () {
    final r = AppRelease.fromJson({
      'version': '1.4.0',
      'build': 90,
      'size': 100,
      'url': '/apk/stable/x.apk',
      'notes': '',
      'channel': 'stable',
    });
    expect(r.forceBelow, 0);
    expect(r.checkHours, 24);
    expect(r.remindHours, 24);
    expect(r.title, '');
    expect(r.isForcedFor(1), isFalse);
  });

  test('服务端策略能读到，数值是 double 也不炸', () {
    final r = AppRelease.fromJson({
      'version': '1.4.0',
      'build': 90,
      'size': 100,
      'url': '/apk/stable/x.apk',
      'force_below': 85.0,
      'check_hours': 6.0,
      'remind_hours': 0.0,
      'title': '有新版本 {version}',
      'message': '当前 {current}，最新 {version}。\n\n{notes}',
    });
    expect(r.forceBelow, 85);
    expect(r.checkHours, 6);
    expect(r.remindHours, 0);
    expect(r.message, contains('{current}'));
  });

  test('force_below 只压更旧的包，不压同版和新版', () {
    final r = _rel(forceBelow: 85);
    expect(r.isForcedFor(84), isTrue);
    expect(r.isForcedFor(85), isFalse);
    expect(r.isForcedFor(86), isFalse);
    // 0 表示不强制，任何版本都能跳过。
    expect(_rel().isForcedFor(1), isFalse);
  });

  test('模板占位符都替换掉，没留花括号', () {
    final r = _rel(
      notes: '修了几处',
      message: '当前 {current}，最新 {version}，{size}。\n{notes}',
    );
    final out = r.fill(r.message, current: '1.3.41 (85)');
    expect(out, contains('1.3.41 (85)'));
    expect(out, contains('1.4.0'));
    expect(out, contains('3.0 MB'));
    expect(out, contains('修了几处'));
    expect(out, isNot(contains('{')));
  });

  test('检查间隔：没到点不查，0 等于每次启动都查', () {
    final h = const Duration(hours: 1).inMilliseconds;
    expect(dueForCheck(now: 10 * h, last: 8 * h, hours: 6), isFalse);
    expect(dueForCheck(now: 10 * h, last: 3 * h, hours: 6), isTrue);
    expect(dueForCheck(now: 10 * h, last: 10 * h - 1, hours: 0), isTrue);
  });

  test('提醒节奏：同包按间隔，换包立刻弹，强制每次都弹', () {
    final h = const Duration(hours: 1).inMilliseconds;
    bool ask({
      required int now,
      required int promptBuild,
      required int promptAt,
      required int build,
      required int remindHours,
      required bool force,
    }) => shouldPrompt(
      now: now,
      promptBuild: promptBuild,
      promptAt: promptAt,
      build: build,
      remindHours: remindHours,
      force: force,
    );

    // 刚弹过同一个包，一小时内不再弹。
    expect(
      ask(
        now: 10 * h,
        promptBuild: 90,
        promptAt: 10 * h - 1,
        build: 90,
        remindHours: 24,
        force: false,
      ),
      isFalse,
    );
    // 过了间隔再弹。
    expect(
      ask(
        now: 40 * h,
        promptBuild: 90,
        promptAt: 10 * h,
        build: 90,
        remindHours: 24,
        force: false,
      ),
      isTrue,
    );
    // 换了新包，跟上次提醒的不是同一个，立刻弹。
    expect(
      ask(
        now: 10 * h,
        promptBuild: 90,
        promptAt: 10 * h - 1,
        build: 91,
        remindHours: 24,
        force: false,
      ),
      isTrue,
    );
    // 强制更新不看提醒记录。
    expect(
      ask(
        now: 10 * h,
        promptBuild: 90,
        promptAt: 10 * h - 1,
        build: 90,
        remindHours: 24,
        force: true,
      ),
      isTrue,
    );
  });

  test('没有下载地址时不拼首页，直接报错', () async {
    final r = AppRelease(
      version: '1.4.0',
      build: 90,
      size: 100,
      url: '',
      notes: '',
      channel: 'stable',
    );
    // 以前这里会请求 `${Api.base}`，拿到 200 的网页存成 .apk，
    // 用户装的时候才看见「解析包出错」。
    await expectLater(
      downloadApk(r, (_) {}),
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'downloadFailed'),
      ),
    );
  });
}
