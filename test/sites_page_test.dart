import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openbbs/l10n/l10n.dart';
import 'package:openbbs/pages/sites_page.dart';
import 'package:openbbs/sites.dart';
import 'package:openbbs/store.dart';

/// 站点管理页：不联网，只摆数据看画得对不对。
///
/// 四条规矩在这里守着：
/// - 主站 / 小站分得清，发帖只在这两类里选；
/// - 副标题只报哪条入口通、多少毫秒，网址一个字都不露；
/// - 主站不给删；
/// - 长按任意一行开始测速。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 出厂预置的入口。全应用只认这个 host 当「主站」，测试里也得用它。
  const v6 = 'https://ipv6bbs.kalutoex.dpdns.org:26016';
  const v4 = 'https://ipv4bbs.kalutoex.dpdns.org:24016';

  /// 一座主站（v6 通、v4 不通，v6 测过 32ms）+ 一座连不上的小站。
  List<SiteEntry> seed() => [
    SiteEntry(id: 'home', name: '时间线', urls: [v6, v4], master: true)
      ..epStatus.addAll({v6: true, v4: false})
      ..epMs[v6] = 32,
    SiteEntry(id: 'sub', name: '二号站', urls: ['http://1.2.3.4:8080'])
      ..reachable = false,
  ];

  Future<void> pumpPage(
    WidgetTester tester,
    List<SiteEntry> sites, {
    String active = 'home',
  }) async {
    final st = AppState.instance;
    final keepSites = st.sites;
    final keepKey = st.activeKey;
    addTearDown(() {
      st.sites = keepSites;
      st.activeKey = keepKey;
    });
    st.sites = sites;
    st.activeKey = active;
    await tester.pumpWidget(const MaterialApp(home: SitesPage()));
    await tester.pump();
  }

  testWidgets('主站小站标得清，副标题只报通不通，不露网址', (tester) async {
    await pumpPage(tester, seed());

    expect(find.text('时间线'), findsOneWidget);
    expect(find.text('二号站'), findsOneWidget);

    // 发帖时能选的只有这两类，列表上先标明。
    expect(find.text('主站'), findsOneWidget);
    expect(find.text('小站'), findsOneWidget);

    // 登录站和当前站都挂在主站那行。
    expect(find.text('登录站'), findsOneWidget);
    expect(find.text('当前'), findsOneWidget);

    // 每条入口一个芯片：测过的带毫秒，没通的打叉。
    expect(find.text('IPv6 ✓ 32ms'), findsOneWidget);
    expect(find.text('IPv4 ✗'), findsOneWidget);

    // 网址是给运维看的，用户不看。
    expect(find.textContaining('kalutoex'), findsNothing);
    expect(find.textContaining('26016'), findsNothing);
    expect(find.textContaining('1.2.3.4'), findsNothing);

    // 连不上的那行给一句话，不弹窗。
    expect(find.text('连不上'), findsOneWidget);
  });

  testWidgets('主站没有可操作项就不挂菜单，小站菜单里有删除', (tester) async {
    await pumpPage(tester, seed());

    Finder rowMenu(String name) => find.descendant(
      of: find.widgetWithText(ListTile, name),
      matching: find.byType(PopupMenuButton<String>),
    );

    // 主站既是当前站又是登录站，三项全被过滤——这行干脆不挂菜单按钮，
    // 点开一个空菜单比没有按钮更让人犯嘀咕。
    expect(rowMenu('时间线'), findsNothing);

    await tester.tap(rowMenu('二号站'));
    await tester.pumpAndSettle();

    expect(find.text('切换'), findsOneWidget);
    expect(find.text('设为登录站'), findsOneWidget);
    expect(find.text('屏蔽'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
  });

  testWidgets('长按开始测速：先报测速中，跑完不留异常', (tester) async {
    await pumpPage(tester, seed());

    await tester.longPress(find.text('二号站'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 提示不排队：新的顶掉旧的，跑完留下的就是结果那条。
    expect(
      find.text(
        Lc.current.siteSpeedResult(Lc.current.siteSpeedNone),
      ),
      findsWidgets,
    );

    // 测试环境的 HTTP 一律回 400：让请求真跑完，别把 future 留到测试之后。
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();

    // 先把入场动画走完（4 秒计时是从动画结束才开始的），再让它到点退场。
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    // 行上不再挂着「测速中…」，说明这轮测速收尾了。
    expect(
      find.descendant(
        of: find.byType(ListTile),
        matching: find.text(Lc.current.siteSpeedRunning),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  test('主站删不掉：removeSite 直接拒，表里一行不少', () async {
    final st = AppState.instance;
    final keepSites = st.sites;
    final keepKey = st.activeKey;
    addTearDown(() {
      st.sites = keepSites;
      st.activeKey = keepKey;
    });

    final sites = seed();
    st.sites = sites;
    st.activeKey = 'home';

    expect(await st.removeSite(sites.first), isFalse);
    expect(st.sites.length, 2);
    expect(st.sites.first.name, '时间线');
  });
}
