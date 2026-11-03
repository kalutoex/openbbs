import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../site_config.dart';
import 'friends_page.dart';

/// 关于：只放开源信息和链接。
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  /// 项目地址来自构建参数 REPO，没配就不显示那一行。
  static String get _repo => SiteConfig.repo;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Text(
              SiteConfig.brand,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
            ),
          ),

          _label(context, '开源'),
          ListTile(
            leading: const Icon(Icons.favorite_border),
            title: const Text('致谢我的朋友们'),
            subtitle: const Text('这里是他们的账号'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const FriendsPage()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('第三方许可证'),
            subtitle: const Text('各依赖自带的许可文本'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showLicensePage(
                context: context, applicationName: SiteConfig.brand),
          ),
          ListTile(
            leading: const Icon(Icons.balance),
            title: const Text('GPL-3.0 许可证'),
            subtitle: const Text('本项目以 GPL-3.0 发布'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _open(context, 'https://www.gnu.org/licenses/gpl-3.0.txt'),
          ),

          _label(context, '链接'),
          if (_repo.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.code),
              title: const Text('源代码'),
              subtitle: Text(_repo.replaceFirst(RegExp(r'^https?://'), '')),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => _open(context, _repo),
            ),
          ListTile(
            leading: const Icon(Icons.bug_report_outlined),
            title: const Text('问题反馈'),
            subtitle: const Text('发现什么不对，记在这里'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _open(context, '$_repo/issues'),
          ),
        ],
      ),
    );
  }

  static Widget _label(BuildContext context, String s) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
    child: Text(
      s,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
        color: Theme.of(context).colorScheme.primary,
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('打不开这个链接')),
      );
    }
  }
}
