import '../app_icon.dart';
import '../widgets/page_width.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../store.dart';

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
      body: ValueListenableBuilder<double>(
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
                const SizedBox(height: 12),
                RepaintBoundary(
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
                                gradient: LinearGradient(colors: _rainbow),
                                border: Border.all(color: sBorder, width: 1.5),
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
                const _IconPicker(),
              ],
            ),
          ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.appIconChanged)),
      );
    } on PlatformException catch (e) {
      // 带上错误码：换不了的时候得能一眼看出是没找到别名，还是系统拒了。
      if (!mounted) return;
      setState(() => _busy = null);
      final detail = e.message?.trim();
      final tail = detail == null || detail.isEmpty
          ? e.code
          : '${e.code}: ${detail.length > 40 ? detail.substring(0, 40) : detail}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${t.appIconUnavailable}（$tail）')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.appIconUnavailable)),
      );
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
