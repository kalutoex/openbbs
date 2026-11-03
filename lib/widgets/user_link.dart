import 'package:flutter/material.dart';

import '../pages/user_page.dart';

/// 用户名 -> 主页。handle 是账号名，空字符串就当没点。
void openUserPage(BuildContext context, String handleOrName) {
  final h = handleOrName.trim().replaceFirst(RegExp(r'^@'), '');
  if (h.isEmpty) return;
  Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => UserPage(name: h)));
}
