import 'package:flutter/material.dart';

import '../widgets/manga_shelf_list.dart';
import '../widgets/page_width.dart';

/// 点作者、点标签进来的结果页。
///
/// 详情页上的作者和标签以前是死字，点了没反应。现在点一下就到这儿：
/// 同一个作者还有哪些书、这个标签下有多少本，按热度排开。
/// 和「更多」那页共用 [MangaShelfList]，样式不用再对一遍。
class MangaFilterPage extends StatelessWidget {
  final String author;
  final String tag;

  const MangaFilterPage({super.key, this.author = '', this.tag = ''});

  bool get _isAuthor => author.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final title = _isAuthor ? '作者 · $author' : '标签 · $tag';
    return Scaffold(
      appBar: AppBar(
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      body: PageWidth(
        max: 900,
        child: MangaShelfList(
          author: author,
          tag: tag,
          showHot: true,
          emptyIcon: Icons.search_off,
          emptyTitle: _isAuthor ? '这个作者没有别的书' : '这个标签下还没有书',
          emptyHint: '库里只有抓下来的那些，搜不到就是没收录',
        ),
      ),
    );
  }
}
