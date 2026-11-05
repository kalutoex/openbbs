import 'package:flutter/material.dart';

/// 网页版没有「手机存储」这回事，入口不显示，页面也不会被推进来。
bool get fileBrowserSupported => false;

class FileBrowserPage extends StatelessWidget {
  const FileBrowserPage({
    super.key,
    this.pickOnly = false,
    this.openOnly = false,
    this.initialPath,
    this.highlight,
  });

  final bool pickOnly;
  final bool openOnly;
  final String? initialPath;
  final String? highlight;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
