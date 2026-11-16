# 第 1 段 · 书架：排序、筛选、搜索、进度

做于 2026-11-16 22:30 – 23:00。范围按 `docs/prompts/06-manga-3-stages.md` 第 1 段。

## 改了什么

### 后端 `bbs/server/app/manga.py`

| 接口 | 改动 | 兼容性 |
|---|---|---|
| `GET /api/manga/shelf` | 加可选 `sort` / `status` / `q`，每本加 `progress` | 不传参数时返回与改前一致 |
| `GET /api/manga/detail/{dir}` | 加 `progress` | 只多一个字段 |

新增三个内部函数：

- `_chapter_order(path)`：读 meta.json，给章节目录顺序。算「读到第几话」要定位下标。
- `_progress_payload(row, order)`：一条 `manga_hist` 记录 → 前端要的进度结构。
- `hist` 一次查全（`WHERE uid=? AND kind='local'`），排序和 payload 共用。

`sort` 取值：

- `recent`（默认）：`-(updated), title`，和原来逐字节一致
- `title`：按书名
- `progress`：读过的按 `viewed_at` 倒序在前，没读过的按书名垫底
- 任何没认出来的值都走 `recent`——参数写错不该让书架变空

`progress` 结构：

```json
{"chapter": "第26话", "chapter_ref": "0300_第26话", "chapter_index": 28,
 "chapter_count": 35, "page": 0, "total": 14, "percent": 0.802,
 "viewed_at": 1794820953}
```

- `page`/`total` 是**话内页数**，不是全书进度——这是 `manga_reader_page.dart:178`
  上报的语义，没改
- `percent = (chapter_index + (page+1)/total) / chapter_count`，用于书架卡片
- `chapter_index = -1` 表示章节表里定位不到（书重抓过、老记录），此时 `percent` 为 null
- **未登录时不返回 `progress` 字段**，前端按未读处理

两个必须注意的点：

1. **进度不能进 `_scan()` 的模块级缓存。** 那份 `_cache` 跨用户共用 20 秒，
   塞进去就是 A 号看到 B 号的进度——第二批 debug 的同类问题，这次没重犯。
   一次请求只查当前用户，一条 SQL。
2. **一次查全，不在循环里单查。** `sort=progress` 需要先知道所有书的 `viewed_at`
   才能排序，所以先一次捞这个用户全部本地历史（admin 只有 13 条），
   再对当前页 12 本算 `percent`。

### 前端

| 文件 | 改动 |
|---|---|
| `lib/manga.dart` | 新增 `MangaProgress`；`MangaBook`/`MangaDetail` 加 `progress`；`MangaApi.shelf` 加参数；查询串抽成 `shelfQuery()` 便于单测 |
| `lib/pages/manga_tab.dart` | 排序菜单、状态筛选 chip、书架内搜索、卡片进度、筛选空态 |
| `lib/pages/manga_detail_page.dart` | 本机没位置时接账号进度；章节格子已读压暗 |
| `lib/read_pos.dart` | 新增 `mangaPosKey()` / `mangaLegacyPosKey()` |
| `lib/pages/manga_reader_page.dart` | 位置 key 改用 `mangaPosKey()` |

界面上的变化：

- AppBar：搜书架（放大镜）｜搜书源（地球）｜排序（三横）｜刷新
- 书架标题行右边：`4047 本`，筛选时变成 `1025 本 · 「花薰」` + 一个「清除」
- 标题行下面一排 chip：全部 / 连载中 / 已完结（值是 `连载` / `完结`，后端子串匹配）
- 卡片第二行：有进度显示 `第26话 · 80%`（主题色），没进度还是 `35 话`
- 搜索是 300ms 防抖，搜索 / 筛选 / 排序任一变化都清列表回顶部重拉

### 顺手修的一个串号

阅读位置的 key 原来是 `manga_pos_<目录>`，**不带账号也不带站点**。
A 号读到第 12 话，换个号登进来看同一本书，直接落到别人的第 12 话上。
和 `ReadPos` 处理帖子是同一个毛病，同一个解法：

```
manga_pos_v2_<站>_<u{uid}|guest>_<目录>
```

老 key 只在新 key 空着时读一次，读到就按新 key 写回；不再往里写。

## 验证

后端（`http://192.168.1.212:8080`，四个进程重启后都验过）：

```
未登录  /shelf?limit=2              字段里没有 progress ✓
sort=title 前 5                      按 Unicode 排 ✓
q=花薰                              total 1，命中《花薰凛然》 ✓
status=连载                         2916 本 ✓
status=完结                         1025 本 ✓
status=连载 & q=百合                 41 本 ✓
sort=zzz                            回落默认顺序 ✓
登录(uid=3) sort=progress 前 4       1794837774 → 1794820953 → 1794820700 → 1794809135，与库里一致 ✓
登录 detail                        progress 章节第26话、index 28、percent 0.802 ✓
```

前端：

```
flutter analyze    No issues found!
flutter test       +117 All tests passed!   （基线 106 + 新增 11）
```

新增 `test/manga_shelf_test.dart` 覆盖：查询串（默认 / 全量 / 中文编码 / 空格 / 排序）、
进度解析（无、正常、index=-1、只有百分比、脏数据）、分页。

## 没验的

- **真机 UI 没走查。** 排序菜单、chip、搜索框在窄屏上的排布只能靠代码推断，
  132px 网格下 AppBar 塞了 4 个图标（搜索/书源/排序/刷新），
  在 360dp 宽的机器上可能挤。等下次打包上机时一起看。
- 4000 本下切排序的实际耗时没测。后端吃 `_scan()` 的 20 秒缓存，
  12 本一次的 `_chapter_order` 读 12 个 meta.json，量级应该是毫秒。
- 搜索只搜书名 / 作者 / 标签，没搜简介——简介在 4000 本上拼起来会慢，
  目前不值得。

## 留的尾巴

- 数据里不少书名前面带一个空格（` マオリス辺境伯的TS漫画`），抓取脚本没 trim，
  `sort=title` 时这些全排在最前面。属于数据问题，接口层没动。
- `manga_hist` 的 `total` 是话内页数，全书百分比靠章节表折。如果一本书
  重新抓过、话数变了，`percent` 会跳一下——可接受，但知道有这回事。
