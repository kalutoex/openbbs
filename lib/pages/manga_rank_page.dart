import 'package:flutter/material.dart';

import '../widgets/manga_shelf_list.dart';
import '../widgets/page_width.dart';
import '../widgets/segmented_pages.dart';

/// 内部书源的整页列表：热度榜 / 最近更新 / 已完结。
///
/// 「推荐」那一排只露十几本，更多就进这里。版式跟「我的-回收站」一套：
/// Scaffold + PageWidth + SegmentedPages，下面是一行一本的列表，
/// 滑到底自动接下一页——不用再端着网格一页页找。
class MangaRankPage extends StatelessWidget {
  const MangaRankPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '内部书源',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      body: PageWidth(
        max: 900,
        child: SegmentedPages(
          labels: const ['热度榜', '最近更新', '已完结'],
          children: const [
            MangaShelfList(
              sort: 'hot',
              emptyTitle: '书库还是空的',
              emptyHint: '抓取那边下完一本，这里就多一本',
            ),
            MangaShelfList(
              sort: 'recent',
              emptyTitle: '书库还是空的',
              emptyHint: '抓取那边下完一本，这里就多一本',
            ),
            MangaShelfList(
              sort: 'hot',
              status: '完结',
              emptyIcon: Icons.done_all,
              emptyTitle: '没有已完结的书',
              emptyHint: '换个标签看看，或者等新书下完',
            ),
          ],
        ),
      ),
    );
  }
}
