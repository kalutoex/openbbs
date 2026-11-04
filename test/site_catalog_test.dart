import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openbbs/pages/site_catalog_page.dart';
import 'package:openbbs/sites.dart';
import 'package:openbbs/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 站点目录 = 主页第二个 tab。它只管「去哪儿看」，
/// 屏蔽过的站不该出现在这里。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  SiteEntry home() => SiteEntry(
    id: 'home',
    name: '时间线',
    urls: ['https://ipv6bbs.kalutoex.dpdns.org:26016'],
    master: true,
  );

  testWidgets('目录列本站和小站，屏蔽过的不出现', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final st = AppState.instance;
    final keep = st.sites;
    addTearDown(() => st.sites = keep);

    st.sites = [
      home(),
      SiteEntry(id: 'sub', name: '二号站', urls: ['http://1.2.3.4:8080']),
      SiteEntry(
        id: 'hidden',
        name: '不想看的站',
        urls: ['http://5.5.5.5:8080'],
        blocked: true,
      ),
    ];

    await tester.pumpWidget(const MaterialApp(home: SiteCatalogPage()));
    // 目录里那张表要从主站拉（测试环境拉不到，退回本地表）。
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();

    expect(find.text('时间线'), findsOneWidget);
    expect(find.text('二号站'), findsOneWidget);
    expect(find.text('不想看的站'), findsNothing);
    // 主站在目录里也标一下，免得跟小站混。
    expect(find.text('主站'), findsOneWidget);
  });

  test('屏蔽开关：小站能开能关，主站不给屏蔽', () async {
    SharedPreferences.setMockInitialValues({});
    final st = AppState.instance;
    final keep = st.sites;
    addTearDown(() => st.sites = keep);

    final h = home();
    final sub = SiteEntry(id: 'sub', name: '二号站', urls: ['http://1.2.3.4:8080']);
    st.sites = [h, sub];

    await st.toggleBlocked(sub);
    expect(sub.blocked, isTrue);
    await st.toggleBlocked(sub);
    expect(sub.blocked, isFalse);

    await st.toggleBlocked(h);
    expect(h.blocked, isFalse);
  });
}
