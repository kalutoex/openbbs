import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../l10n/l10n.dart';
import '../power.dart';

/// 电池优化豁免。锁屏后收不到提醒，八成是这里没开。
///
/// 豁免只能由用户在系统弹窗里点「允许」，代码点不了，所以这一行只是个入口：
/// 点完回来重新读一次状态，不假装已经成功了。已经在白名单里的再点，
/// 就当用户想去系统里关掉，直接送进应用设置。
class KeepAliveTile extends StatefulWidget {
  const KeepAliveTile({super.key});

  @override
  State<KeepAliveTile> createState() => _KeepAliveTileState();
}

class _KeepAliveTileState extends State<KeepAliveTile>
    with WidgetsBindingObserver {
  bool? _on;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // 系统弹窗挡在 App 上面，回来才知道点没点。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final v = await Power.ignoringBattery();
    if (!mounted) return;
    setState(() => _on = v);
  }

  Future<void> _tap() async {
    if (_on == true) {
      await openAppSettings();
      return;
    }
    await Power.requestIgnore();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.battery_saver_outlined),
      title: Text(Lc.current.bgKeepAlive),
      subtitle: Text(Lc.current.bgKeepAliveHint),
      trailing: Text(
        _on == true ? Lc.current.bgKeepAliveOn : Lc.current.bgKeepAliveOff,
        style: TextStyle(
          fontSize: 12,
          color: _on == true
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.outline,
        ),
      ),
      onTap: _tap,
    );
  }
}
