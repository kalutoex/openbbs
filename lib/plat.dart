import 'package:flutter/foundation.dart';

/// 系统媒体库（安卓 MediaStore / iOS 相册）只有手机上有。
/// 桌面和网页都退回系统文件对话框。
bool get hasMediaStore =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// 桌面三件套：窗口大、没有相册、没有「安装未知应用」这一套。
bool get isDesktop =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS);
