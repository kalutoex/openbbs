import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openbbs/pages/sites_page.dart';
import 'package:openbbs/sites.dart';
import 'package:openbbs/store.dart';

/// 站点管理页的冒烟：不联网，只摆数据看画得对不对。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('列表显示站点名、主机名和登录站标记', (tester) async {
    final st = AppState.instance;
    final keepSites = st.sites;
    final keepKey = st.activeKey;
    addTearDown(() {
      st.sites = keepSites;
      st.activeKey = keepKey;
    });
    st.sites = [
      SiteEntry(
        id: 's1',
        name: '一号站',
        urls: ['https://ipv6bbs.example.org', 'https://ipv4bbs.example.org'],
        master: true,
      ),
      SiteEntry(id: 's2', name: '二号站', urls: ['http://1.2.3.4:8080'])
        ..reachable = false,
    ];
    st.activeKey = 's1';

    await tester.pumpWidget(const MaterialApp(home: SitesPage()));
    await tester.pump();

    expect(find.text('一号站'), findsOneWidget);
    expect(find.text('二号站'), findsOneWidget);
    // 登录站标记 + 当前标记都在第一行上。
    expect(find.text('登录站'), findsOneWidget);
    expect(find.text('当前'), findsOneWidget);
    // 连不上的那行副标题带「连不上」。
    expect(find.textContaining('连不上'), findsOneWidget);
  });

  testWidgets('空表给引导，不崩', (tester) async {
    final st = AppState.instance;
    final keepSites = st.sites;
    addTearDown(() => st.sites = keepSites);
    st.sites = [];

    await tester.pumpWidget(const MaterialApp(home: SitesPage()));
    await tester.pump();

    expect(find.text('还没有站点'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsWidgets);
  });
}
