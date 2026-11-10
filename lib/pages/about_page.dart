import '../widgets/page_width.dart';
import '../widgets/app_card.dart';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../site_config.dart';
import 'easter_egg_page.dart';
import 'friends_page.dart';

import '../l10n/l10n.dart';
import '../widgets/toast.dart';

/// 关于：只放开源信息和链接。
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  /// 项目地址来自构建参数 REPO，没配就不显示那一行。
  String get _repo => SiteConfig.repo;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(Lc.current.about)),
      body: PageWidth(
        max: 560,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 40),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 6),
              child: Text(
                SiteConfig.brand,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),

            _label(context, Lc.current.openSource),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.favorite_border),
                    title: Text(Lc.current.thanksFriends),
                    subtitle: Text(Lc.current.thanksFriendsSub),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const FriendsPage()),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: Text(Lc.current.thirdPartyLicenses),
                    subtitle: Text(Lc.current.thirdPartyLicensesSub),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => showLicensePage(
                      context: context,
                      applicationName: SiteConfig.brand,
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.balance),
                    title: Text(Lc.current.gplLicense),
                    subtitle: Text(Lc.current.gplLicenseSub),
                    trailing: const Icon(Icons.open_in_new, size: 18),
                    onTap: () => _open(
                      context,
                      'https://www.gnu.org/licenses/gpl-3.0.txt',
                    ),
                  ),
                ],
              ),
            ),
            _label(context, Lc.current.links),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Column(
                children: [
                  if (_repo.isNotEmpty)
                    ListTile(
                      leading: const Icon(Icons.code),
                      title: Text(Lc.current.sourceCode),
                      subtitle: Text(
                        _repo.replaceFirst(RegExp(r'^https?://'), ''),
                      ),
                      trailing: const Icon(Icons.open_in_new, size: 18),
                      onTap: () => _open(context, _repo),
                    ),
                  ListTile(
                    leading: const Icon(Icons.bug_report_outlined),
                    title: Text(Lc.current.issues),
                    subtitle: Text(Lc.current.issuesSub),
                    trailing: const Icon(Icons.open_in_new, size: 18),
                    onTap: () => _open(context, '$_repo/issues'),
                  ),
                ],
              ),
            ),

            // 没啥用的小按钮。点几下都没反应，连着点五下才开门。
            const SizedBox(height: 10),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 2),
              onTap: _tap,
              child: ListTile(
                title: Text(
                  Lc.current.easterEggButton,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 连点计数。4 次以内一律没反应，第 5 次进彩蛋页。
  /// 隔 3 秒没再点就归零——不然一路点下来攒够五下，反而容易被误触打开。
  int _taps = 0;
  DateTime? _lastTap;

  void _tap() {
    final now = DateTime.now();
    if (_lastTap != null &&
        now.difference(_lastTap!) > const Duration(seconds: 3)) {
      _taps = 0;
    }
    _lastTap = now;
    _taps++;
    if (_taps < 5) return;
    _taps = 0;
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const EasterEggPage()));
  }

  static Widget _label(BuildContext context, String s) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 18, 12, 6),
    child: Text(
      s,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );

  Future<void> _open(BuildContext context, String url) async {
    var ok = false;
    try {
      ok = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      ok = false;
    }
    if (!ok && context.mounted) {
      toast(context, Lc.current.cantOpenLink);
    }
  }
}
