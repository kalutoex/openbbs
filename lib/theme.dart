import 'package:flutter/material.dart';

/// 整套 MD3 外观收在这里：页面只管结构，长相由这里定。
///
/// 从记事本（rainn_note）那版搬过来的，原来这边只有一句
/// ColorScheme.fromSeed，组件样式全靠各页面手写，主题色一换
/// 界面并不会整体跟着变。
ThemeData buildAppTheme(Brightness brightness, Color seed) {
  final scheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: brightness,
  ).copyWith(primary: seed);

  // 只为了取一份基准 TextTheme，组件主题要引用它。
  final text = ThemeData(useMaterial3: true, colorScheme: scheme).textTheme;

  // 卡片的边线：浅色下靠它把卡片从背景里拉出来，暗色下压暗一点别刺眼。
  final hairline = BorderSide(
    color: scheme.outlineVariant.withValues(
      alpha: brightness == Brightness.light ? .55 : .35,
    ),
  );

  const shapeM = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(12)),
  );
  const shapeL = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(16)),
  );
  const shapeXL = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(28)),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    textTheme: text,

    // 顶栏跟表面同色，内容滚到下面时靠 surfaceTint 自己染色。
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: scheme.surfaceTint,
      elevation: 0,
      scrolledUnderElevation: 3,
      centerTitle: false,
      titleTextStyle: text.titleLarge?.copyWith(
        color: scheme.onSurface,
        fontWeight: FontWeight.w600,
        fontSize: 24,
      ),
      iconTheme: IconThemeData(color: scheme.onSurfaceVariant),
      actionsIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
    ),

    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLow,
      surfaceTintColor: scheme.surfaceTint,
      shadowColor: scheme.shadow,
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(16)),
        side: hairline,
      ),
    ),

    listTileTheme: ListTileThemeData(
      shape: shapeM,
      iconColor: scheme.onSurfaceVariant,
      textColor: scheme.onSurface,
    ),

    // 顶部切换用圆角小块，别用默认那根下划线——和卡片语言不搭。
    tabBarTheme: TabBarThemeData(
      indicatorSize: TabBarIndicatorSize.label,
      indicator: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: const BorderRadius.all(Radius.circular(20)),
      ),
      dividerColor: Colors.transparent,
      labelColor: scheme.onSecondaryContainer,
      unselectedLabelColor: scheme.onSurfaceVariant,
      labelStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      unselectedLabelStyle: text.labelLarge,
    ),

    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),

    // filled 变体：无描边，聚焦时才浮出一圈主题色。
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(28)),
        borderSide: BorderSide.none,
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(28)),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(28)),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      hintStyle: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: shapeXL,
        minimumSize: const Size(0, 48),
        textStyle: text.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: shapeXL,
        minimumSize: const Size(0, 48),
        textStyle: text.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: shapeXL, textStyle: text.labelLarge),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: scheme.onSurfaceVariant),
    ),

    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primaryContainer,
      foregroundColor: scheme.onPrimaryContainer,
      elevation: 3,
      shape: shapeL,
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      surfaceTintColor: scheme.surfaceTint,
      elevation: 0,
      shape: shapeXL,
      titleTextStyle: text.headlineSmall?.copyWith(color: scheme.onSurface),
      contentTextStyle: text.bodyMedium?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
    ),

    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: text.bodyMedium?.copyWith(
        color: scheme.onInverseSurface,
      ),
      actionTextColor: scheme.inversePrimary,
      shape: shapeM,
      elevation: 3,
    ),

    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return scheme.onPrimary;
        return scheme.outline;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return scheme.primary;
        return scheme.surfaceContainerHighest;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Colors.transparent;
        return scheme.outline;
      }),
    ),

    progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),

    // 底部导航：选中项文字加粗、图标换实心由各页面自己给，
    // 这里只管底色、字号和未选中的灰。
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 64,
      indicatorColor: scheme.secondaryContainer,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final on = states.contains(WidgetState.selected);
        return text.labelMedium?.copyWith(
          fontSize: 11.5,
          fontWeight: on ? FontWeight.w600 : FontWeight.w500,
          color: on ? scheme.onSurface : scheme.onSurfaceVariant,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final on = states.contains(WidgetState.selected);
        return IconThemeData(
          size: 24,
          color: on ? scheme.onSecondaryContainer : scheme.onSurfaceVariant,
        );
      }),
    ),

    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surfaceContainerHigh,
      surfaceTintColor: scheme.surfaceTint,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(16)),
        side: hairline,
      ),
      textStyle: text.bodyMedium?.copyWith(color: scheme.onSurface),
    ),

    // 底部菜单统一带拖手柄、圆角上沿，和对话框一个语言。
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      modalBackgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: scheme.surfaceTint,
      showDragHandle: true,
      elevation: 0,
      modalElevation: 0,
      dragHandleColor: scheme.outlineVariant,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),

    chipTheme: ChipThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      selectedColor: scheme.secondaryContainer,
      side: hairline,
      shape: const StadiumBorder(),
      labelStyle: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
      secondaryLabelStyle: text.labelMedium?.copyWith(
        color: scheme.onSecondaryContainer,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    ),

    badgeTheme: BadgeThemeData(
      backgroundColor: scheme.error,
      textColor: scheme.onError,
      smallSize: 7,
      largeSize: 16,
      textStyle: text.labelSmall?.copyWith(
        color: scheme.onError,
        fontWeight: FontWeight.w600,
      ),
    ),

    // 页面切换。默认的 Zoom 是缩放淡入，暗色下边角会露一下底色，
    // 看着像"闪"。换成 M3 的 fade-forwards，横向推进，没有缩放。
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.fuchsia: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
      },
    ),
  );
}
