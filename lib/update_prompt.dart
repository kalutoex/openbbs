import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n/l10n.dart';
import 'open_path.dart';
import 'plat.dart';
import 'update.dart';
import 'widgets/toast.dart';

// 和设置页共用这几个键，名字别改。
const _kBetaPref = 'update_beta';
const _kLastCheck = 'update_last_check'; // 上次成功问服务器的时间（毫秒）
const _kCheckHours = 'update_check_hours'; // 上次服务端给的间隔
const _kPromptBuild = 'update_prompt_build'; // 上次弹出提示的 build
const _kPromptAt = 'update_prompt_at'; // 上次弹出的时间（毫秒）

String _localVersion(PackageInfo? p) =>
    p == null ? '' : p.version; // 构建号是内部的东西，界面上不露

/// 距上次检查够不够久。[hours] 是服务端上次给的间隔，0 表示每次启动都查。
bool dueForCheck({required int now, required int last, required int hours}) =>
    hours <= 0 || now - last >= Duration(hours: hours).inMilliseconds;

/// 这个版本该不该弹。
///
/// 强制更新每次都弹；同一个包提醒过、还没到下次提醒时间就不再烦人。
bool shouldPrompt({
  required int now,
  required int promptBuild,
  required int promptAt,
  required int build,
  required int remindHours,
  required bool force,
}) {
  if (force) return true;
  if (promptBuild != build) return true;
  if (remindHours <= 0) return true;
  return now - promptAt >= Duration(hours: remindHours).inMilliseconds;
}

/// 启动时问一次有没有新版本。
///
/// 失败一律静默：检查更新出问题不该拦住人用 App。
/// 网页版不查——网页本身就是服务器发出来的，刷新即最新。
Future<void> checkOnStart(BuildContext context) async {
  if (kIsWeb) return;

  final sp = await SharedPreferences.getInstance();
  final now = DateTime.now().millisecondsSinceEpoch;
  final last = sp.getInt(_kLastCheck) ?? 0;
  final hours = sp.getInt(_kCheckHours) ?? 24;

  // 服务端定的间隔还没到就不问；0 表示每次启动都问。
  if (!dueForCheck(now: now, last: last, hours: hours)) return;
  // 防止反复冷启动时连着打服务器，最少隔十分钟。
  if (now - last < const Duration(minutes: 10).inMilliseconds) return;

  AppRelease rel;
  try {
    rel = await fetchLatest(beta: sp.getBool(_kBetaPref) ?? false);
  } catch (_) {
    return;
  }
  await sp.setInt(_kLastCheck, now);
  await sp.setInt(_kCheckHours, rel.checkHours < 0 ? 0 : rel.checkHours);

  final pkg = await PackageInfo.fromPlatform();
  final local = int.tryParse(pkg.buildNumber) ?? 0;
  if (rel.build <= local) return;

  final force = rel.isForcedFor(local);
  // 同一个包，刚提醒过还没到下次提醒时间，就不烦第二次。强制更新不看这个。
  if (!shouldPrompt(
    now: now,
    promptBuild: sp.getInt(_kPromptBuild) ?? 0,
    promptAt: sp.getInt(_kPromptAt) ?? 0,
    build: rel.build,
    remindHours: rel.remindHours,
    force: force,
  )) {
    return;
  }

  if (!context.mounted) return;
  final go = await showUpdatePrompt(context, rel, current: pkg);
  await sp.setInt(_kPromptBuild, rel.build);
  await sp.setInt(_kPromptAt, now);
  if (go && context.mounted) await installApk(context, rel);
}

/// 有新版时的弹窗。返回用户是否选择了下载安装。
Future<bool> showUpdatePrompt(
  BuildContext context,
  AppRelease r, {
  PackageInfo? current,
}) async {
  final local = current == null ? '' : _localVersion(current);
  final force =
      current != null && r.isForcedFor(int.tryParse(current.buildNumber) ?? 0);
  final fallbackBody = r.notes.isEmpty
      ? Lc.current.installOverwrite(r.sizeText)
      : Lc.current.releaseNotes(r.notes, r.sizeText);
  final body = r.message.isEmpty
      ? fallbackBody
      : r.fill(r.message, current: local);
  final title = r.title.isEmpty
      ? (r.channel == 'beta'
            ? Lc.current.betaVersion(r.version)
            : Lc.current.newVersion(r.version))
      : r.fill(r.title, current: local);

  final go = await showDialog<bool>(
    context: context,
    barrierDismissible: !force,
    builder: (c) => PopScope(
      // 强制更新时，返回键也不该把弹窗关掉。
      canPop: !force,
      child: AlertDialog(
        title: Text(title),
        content: ConstrainedBox(
          // 小屏（手表）上不加这层，正文会把按钮顶出可视区。
          constraints: BoxConstraints(
            maxHeight: (MediaQuery.of(c).size.height * 0.5).clamp(96.0, 340.0),
          ),
          child: SingleChildScrollView(
            child: Text(force ? '${Lc.current.mustUpdate}\n\n$body' : body),
          ),
        ),
        actions: [
          if (!force)
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(Lc.current.later),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(Lc.current.downloadAndInstall),
          ),
        ],
      ),
    ),
  );
  return go == true;
}

/// 下载安装包交给系统安装器。网页版不会走到这里。
Future<void> installApk(BuildContext context, AppRelease r) async {
  // 用 ValueNotifier 推进度：弹窗里的 StatefulBuilder 拿不到外面的 setState。
  final prog = ValueNotifier<double>(0);
  final nav = Navigator.of(context);
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: Text(Lc.current.downloading),
        content: ValueListenableBuilder<double>(
          valueListenable: prog,
          builder: (_, v, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: v <= 0 ? null : v),
              const SizedBox(height: 14),
              Text('${(v * 100).toStringAsFixed(0)}%'),
            ],
          ),
        ),
      ),
    ),
  );
  try {
    final file = await downloadApk(r, (v) => prog.value = v);
    if (context.mounted) nav.pop();
    await openLocalFile(file.path);
    if (!context.mounted) return;
    toast(
      context,
      isDesktop ? Lc.current.handedToSystem : Lc.current.handedToInstaller,
    );
  } catch (e) {
    if (context.mounted) nav.pop();
    if (!context.mounted) return;
    toast(context, Lc.current.downloadFailedWith('$e'));
  }
}
