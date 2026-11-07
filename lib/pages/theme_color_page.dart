import '../app_icon.dart';
import '../widgets/page_width.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../store.dart';
import '../user_color.dart';
import '../widgets/toast.dart';

import '../l10n/error_text.dart';
import '../l10n/l10n.dart';

/// 36 档，0° 到 350°，和 AppState 的色相范围、Slider 的 max 对齐。
/// （37 档会走到 360°，等于 0°，色环首尾重复。）
final _rainbow = List.generate(
  36,
  (i) => HSVColor.fromAHSV(1.0, i * 10.0, 1.0, 0.9).toColor(),
);

/// 主题色。记事本那边搬过来的那条色带：拖的其实是彩虹本身。
class ThemeColorPage extends StatelessWidget {
  const ThemeColorPage({super.key});

  @override
  Widget build(BuildContext context) {
    final st = AppState.instance;
    final t = Theme.of(context);
    final scheme = t.colorScheme;
    final sBorder = scheme.outlineVariant;
    // 滑块压在彩虹上，得挑一个跟任何色相都拉得开对比的颜色。
    final tFill = scheme.onSurface;

    return Scaffold(
      appBar: AppBar(title: Text(Lc.current.accentColor)),
      body: ListenableBuilder(
        listenable: st.useDynamicColor,
        builder: (context, _) {
          final dyn = st.useDynamicColor.value;
          return ValueListenableBuilder<double>(
            valueListenable: st.accentHue,
            builder: (context, hue, _) => PageWidth(
              max: 520,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      Lc.current.themeColorTitle,
                      style: t.textTheme.titleMedium,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: dyn,
                      onChanged: st.setUseDynamicColor,
                      title: Text(Lc.current.followWallpaper),
                      subtitle: Text(
                        Lc.current.followWallpaperHint,
                        style: t.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Opacity(
                      opacity: dyn ? .35 : 1,
                      child: IgnorePointer(
                        ignoring: dyn,
                        child: RepaintBoundary(
                          child: SizedBox(
                            height: 100,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  top: 34,
                                  bottom: 34,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: _rainbow,
                                        ),
                                        border: Border.all(
                                          color: sBorder,
                                          width: 1.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                // 轨道压成 0 高度、透明，只留拇指，拖的是那条彩虹。
                                Positioned.fill(
                                  child: SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      trackHeight: 0,
                                      activeTrackColor: Colors.transparent,
                                      inactiveTrackColor: Colors.transparent,
                                      thumbColor: tFill,
                                      overlayColor: Colors.transparent,
                                      thumbShape: const RoundSliderThumbShape(
                                        enabledThumbRadius: 12.5,
                                      ),
                                    ),
                                    child: Slider(
                                      value: hue,
                                      min: AppState.minHue,
                                      max: AppState.maxHue,
                                      onChanged: st.previewHue,
                                      onChangeEnd: st.setAccentHue,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: st.colorOfHue(hue),
                            shape: BoxShape.circle,
                            border: Border.all(color: sBorder, width: 1.5),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          AppState.hueName(hue),
                          style: t.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    Text(
                      Lc.current.accentColorHint,
                      style: t.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const _MyColorPicker(),
                    const _IconPicker(),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}


/// 我的消息颜色。只影响私信里自己那条气泡，不跟着 App 主题色走——
/// 主题色是「我这台设备看着舒服」，这个是「别人看我的时候是什么色」。
class _MyColorPicker extends StatefulWidget {
  const _MyColorPicker();

  @override
  State<_MyColorPicker> createState() => _MyColorPickerState();
}

class _MyColorPickerState extends State<_MyColorPicker> {
  int? _sel;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final c = AppState.instance.user?['color'];
    _sel = c is int && c >= 0 ? c : null;
  }

  Future<void> _pick(int? hue) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final d = await Api.patch('/me', {'color': hue ?? -1});
      final u = d is Map ? d['user'] : null;
      if (u is Map<String, dynamic>) AppState.instance.applyUser(u);
      if (!mounted) return;
      setState(() {
        _sel = hue;
        _busy = false;
      });
      toast(context, Lc.current.saved);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      toast(context, errorText(context, e));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      toast(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final scheme = t.colorScheme;
    final dark = t.brightness == Brightness.dark;
    final mine = _sel ?? hueOfUser(AppState.instance.user);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 28),
        Text(Lc.current.myMessageColor, style: t.textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(
          Lc.current.myMessageColorHint,
          style: t.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        // 先给一条预览：跟我聊天的人看到的就是这个样子
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: bubbleMineBg(mine, dark),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(6),
                ),
              ),
              child: Text(
                Lc.current.send,
                style: TextStyle(fontSize: 14, color: bubbleMineFg(mine)),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              _sel == null ? Lc.current.myMessageColorAuto : '${_sel!}°',
              style: t.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (_busy) ...[
              const SizedBox(width: 10),
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (var i = 0; i < 36; i++)
              _swatch(i * 10, i * 10 == _sel),
            _autoSwatch(),
          ],
        ),
      ],
    );
  }

  Widget _swatch(int hue, bool on) {
    final c = HSLColor.fromAHSL(1, hue.toDouble(), 0.55, 0.55).toColor();
    return InkWell(
      onTap: _busy ? null : () => _pick(hue),
      customBorder: const CircleBorder(),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: c,
          shape: BoxShape.circle,
          border: Border.all(
            color: on
                ? Theme.of(context).colorScheme.onSurface
                : Colors.transparent,
            width: 2.5,
          ),
        ),
        child: on
            ? const Icon(Icons.check, size: 17, color: Colors.white)
            : null,
      ),
    );
  }

  Widget _autoSwatch() {
    final on = _sel == null;
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: _busy ? null : () => _pick(null),
      customBorder: const CircleBorder(),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          shape: BoxShape.circle,
          border: Border.all(
            color: on ? cs.onSurface : cs.outlineVariant,
            width: on ? 2.5 : 1,
          ),
        ),
        child: Icon(
          Icons.autorenew,
          size: 16,
          color: on ? cs.onSurface : cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 桌面图标。系统层换图标只能靠清单里预置的别名，这里只是挑启用哪一个，
/// 所以下面这些是固定的 8 套，不是随便挑图。
class _IconPicker extends StatefulWidget {
  const _IconPicker();

  @override
  State<_IconPicker> createState() => _IconPickerState();
}

class _IconPickerState extends State<_IconPicker> {
  String? _current;
  String? _busy;

  @override
  void initState() {
    super.initState();
    currentAppIcon().then((v) {
      if (mounted) setState(() => _current = v);
    });
  }

  Future<void> _pick(String key) async {
    if (_busy != null || key == _current) return;
    setState(() => _busy = key);
    final t = Lc.current;
    try {
      await setAppIcon(key);
      if (!mounted) return;
      setState(() {
        _current = key;
        _busy = null;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t.appIconChanged)));
    } on PlatformException catch (e) {
      // 带上错误码：换不了的时候得能一眼看出是没找到别名，还是系统拒了。
      if (!mounted) return;
      setState(() => _busy = null);
      final detail = e.message?.trim();
      final tail = detail == null || detail.isEmpty
          ? e.code
          : '${e.code}: ${detail.length > 40 ? detail.substring(0, 40) : detail}';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${t.appIconUnavailable}（$tail）')));
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = null);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t.appIconUnavailable)));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!canChangeAppIcon) return const SizedBox.shrink();
    final t = Theme.of(context);
    final scheme = t.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 28),
        Text(Lc.current.appIconTitle, style: t.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          Lc.current.appIconHint,
          style: t.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            for (final o in appIconOptions)
              _IconTile(
                option: o,
                selected: o.key == _current,
                busy: o.key == _busy,
                onTap: () => _pick(o.key),
              ),
          ],
        ),
      ],
    );
  }
}

class _IconTile extends StatelessWidget {
  const _IconTile({
    required this.option,
    required this.selected,
    required this.busy,
    required this.onTap,
  });

  final AppIconOption option;
  final bool selected;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: 64,
        child: Column(
          children: [
            Stack(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected ? scheme.primary : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(appIconAsset(option.key)),
                  ),
                ),
                if (busy)
                  const Positioned.fill(
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              option.label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
