import 'package:flutter/material.dart';

/// 全局的导航与提示入口。
///
/// 上传这类活儿已经不在某个页面里跑了，收尾时页面可能早没了，
/// 得有一个不依赖哪个 State 的地方能弹一句话、能跳一下。
final GlobalKey<NavigatorState> appNav = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> appMessenger =
    GlobalKey<ScaffoldMessengerState>();
