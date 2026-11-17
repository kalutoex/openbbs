# 第 1 段：继续阅读与阅读器收尾

2026-11-17 17:40 完成。对应 `docs/prompts/07-manga-opt-3-stages.md` 第 1 段。

## 改了什么

| 文件 | 改动 |
|---|---|
| `lib/manga_user.dart` | `hist()` 加 `limit` 参数（走 query，不拼在 path 里） |
| `lib/img_size_store.dart` | 加 `ensureLoaded()`——纵向估算位置要用尺寸表，`get` 是同步的 |
| `lib/pages/manga_tab.dart` | 书架顶「继续阅读」行（数据、卡片、直接进阅读器） |
| `lib/pages/manga_reader_page.dart` | 纵向位置恢复、跳页、读完一话的出口、切读法后停在同一页 |

### 1. 继续阅读

- 数据：`GET /api/manga/history?limit=12`，前端滤 `kind == 'local'`，取前 3
- 位置：推荐横滑**上方**；搜索态或有关键词时整行不渲染
- 卡片：46×62 封面 + 书名 + 「第N话 · 67%」，点开先取详情，再带 `initialPage` 进阅读器
- 取不到（未登录、断网）就静默不显示，书架照常
- 刷新时机：进页、下拉刷新、`mangaBump`、从阅读器返回

### 2. 纵向位置恢复

- 位置存档本来就有（`manga_pos_v2_<站>_<uid>_<目录>`，存 `章节目录|页号`），缺的是纵向不认它
- 纵向偏移按「前面几页一共多高」算：优先用 `ImgSizeStore` 里记过的真实宽高
  （读过的页都存过），没见过的按宽度 × 1.45 估
- 跳完再对最多 3 次（间隔 260 ms）——图一张张回来，`maxScrollExtent` 一直在长

### 3. 跳页

- 底部栏中间「12 / 45」改成可点，弹输入框，只收数字，越界落两头
- 横向 `animateToPage`，纵向按估算偏移 `animateTo`
- **和提示词的一处偏差**：提示词写"顶部栏加页码按钮"，顶部已挤了返回/标题/切读法/亮度四个控件，
  改成复用底部已有的页码文字，位置更顺手

### 4. 读完一话的出口

- 横向看最后一页、纵向滚到剩 160 px 以内，右下浮「下一话」
- 最后一话显示「已是最后一话」，点了退回详情页
- 点完 2 秒内不再弹（`_endMutedUntil`），避免动画过渡期闪
- 一话短到撑不满一屏时滚不动，`ScrollMetricsNotification` 里补判一次，不至于没出口

### 5. 附带修的

切横向/纵向原来会退回第一页（两套视图各有滚动状态，没人把当前页带过去）。
现在切换后 `addPostFrameCallback` 里调 `_jumpToPage(当前页)`。

## 验证

```
flutter analyze --no-pub   →  No issues found! (ran in 5.0s)
flutter test --no-pub      →  00:40 +133: All tests passed!
```

`dart format` 跑过两个页面文件。

## 没验的

- **真机没验**。手上没有设备，以下三条只能等装机后走一遍：
  1. 纵向读到第 7 页退出再进，落点是否在第 7 页（±1 页内算过）
  2. 跳页输入 999 是否落最后一页
  3. 单页章节的「下一话」是否浮出来
- 「继续阅读」依赖登录态；未登录的路径只走了 catch 分支的代码逻辑，没实际跑

## 已知取舍

- 纵向恢复是估算，不是精确落页。原因是图片高度只有解码后才知道；
  若要像素级准确，得给每页开 `probeSize`，一话 50 页就多 50 次探测请求，不值。
- `_askJump` 里 `TextEditingController` 在 dialog 关闭后立刻 dispose，正常路径没问题；
  若某天改成 Non-dismissible 需重新确认。
