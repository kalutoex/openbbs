import 'package:flutter/material.dart';

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
        builder: (context, hue, _) => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(Lc.current.themeColorTitle, style: t.textTheme.titleMedium),
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
            ],
          ),
        ),
      ),
    );
  }
}
