import 'package:flutter/widgets.dart';

import '../api.dart';
import 'app_localizations.dart';

/// 把错误翻成当前语言的文案。
///
/// 两种来源分开处理：
/// - 客户端自己抛的（[ApiException.code] 非空）：message 是写死的中文，
///   不能被信任，一律按 code 查 ARB。
/// - 服务端下发的（code 为 null）：message 是原文，直接显示。
///   要不要翻译由服务端决定，客户端不猜。
///
/// 界面显示错误时统一走这个，不要再直接写 `e.message`。
String errorText(BuildContext context, Object error) {
  if (error is! ApiException) return '$error';
  final code = error.code;
  if (code == null) return error.message;

  final l = L.of(context);
  final status = error.status ?? 0;
  return switch (code) {
    'notConfigured' => l.errNotConfigured,
    'uploadNoUrl' => l.errUploadNoUrl,
    'uploadFailed' => l.errUploadFailed(error.detail ?? ''),
    'badResponse' => l.errBadResponse(status),
    'requestFailed' => l.errRequestFailed(status),
    'downloadFailed' => l.errDownloadFailed(status),
    'connectFailed' => l.connectFailed(error.detail ?? ''),
    // 新增 code 忘了在这里接上时，至少还能看见原文，不至于变成空字符串。
    _ => error.message,
  };
}
