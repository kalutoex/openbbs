import 'package:flutter/material.dart';

import '../store.dart';
import '../l10n/l10n.dart';
import '../widgets/app_card.dart';
import '../widgets/page_width.dart';

/// 彩蛋页：放在这里的东西都不上台面，但都是真做过的。
///
/// 入口在「关于」最下面那一栏，连点五下才进得来，正常人看不到。
class EasterEggPage extends StatelessWidget {
  const EasterEggPage({super.key});

  @override
  Widget build(BuildContext context) {
    final st = AppState.instance;
    return Scaffold(
      appBar: AppBar(title: Text(Lc.current.easterEggTitle)),
      body: PageWidth(
        max: 560,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 40),
          children: [
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: ValueListenableBuilder<bool>(
                valueListenable: st.hueCards,
                builder: (_, v, _) => SwitchListTile(
                  title: Text(Lc.current.hueCards),
                  value: v,
                  onChanged: st.setHueCards,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
