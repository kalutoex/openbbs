# 漫画区第二轮优化提示词（三段）

写于 2026-11-17 17:20。范围：`openbbs`（Flutter 客户端）+ `bbs/server`（FastAPI 后端）的漫画部分。
承接 `06-manga-3-stages.md`（第 1、2 段已完成，第 3 段离线下载尚未执行）。

## 为什么有这份

书库已经从 4000 部长到 21868 本（2026-11-17 13:45 抓完第二批），
06 解决的"能管"在 4000 本规模成立，2 万本规模下露出新的问题：
找不到在读的书、封面每次重下原图、坏书没人发现、同名书分不清。

本轮六项，按"合起来才成立"切成三段：

| # | 项 | 为什么现在做 |
|---|---|---|
| 1 | 继续阅读入口 | 2 万本里找回上次读的那本，现在要手动切一次排序 |
| 2 | 阅读器收尾 | 纵向模式记不住位置、不能跳页、读完一话没有出口 |
| 3 | 封面缩略图 | 列表用 28 KB 原图，一屏 20 张近 600 KB |
| 4 | 书库巡检 | 2 万本里缺页、坏图，靠肉眼发现不了 |
| 5 | 同名书区分 | 68 组同名，书架里两本一样的标题，分不清 |
| 6 | 离线下载 | 06 第 3 段，一直没做；地铁里打开是一片裂图 |

**关于"分卷"：本文件不合并分卷。** 2026-11-17 核对：21868 个目录里同名 68 组（140 个目录），
抽查 `●REC`、`精灵幻想记`、`阿松` 三组，全部是**不同作者、不同话数的不同作品**，
只是标题撞了。合并会把不相干的书缝在一起，比不合并更糟。源站本来就拆成"第一部/第四部"的那批
（如 `东方三月精`），在源站就是独立条目，也不动。这条只做前端区分，见第 2 段第 3 项。

## 盘面事实（2026-11-17 17:20 核对）

### 后端

- `bbs/server/app/manga.py`，14 个接口，前缀 `/api/manga`：
  `/shelf`（支持 `sort=hot|recent|title|progress`、`status`、`q`、`author`、`tag`、`offset`、`limit`）、
  `/detail/{dir}`、`/chapter/{dir}/{chapter_dir}`、`/fav/state`、`/fav`、`/fav/seen`、`/favs`、
  `/history`（POST/GET/DELETE）、`/recommend`、`/rank`、`/zmh/*` 三件套
- 书库扫描已改成增量：`_scan()` 读 `/vol2/1000/manga/_scan_index.json`，
  首次 1.6 秒、命中 0.03 秒，全量重建 97 秒（今天实测）
- 图片走静态挂载：`app/main.py:36` `app.mount("/manga", StaticFiles(directory="/vol2/1000/manga"))`
- 数据库 `manga_hist` 已有 `chapter / chapter_ref / page / total / viewed_at`；
  `/shelf` 已能把进度 join 成每本的 `progress`
- 服务端 venv 有 **Pillow 13.0.0**，可以批量转图

### 客户端

- 版本 `1.1.5+100171`
- `manga_tab.dart`：推荐横滑（`_recRow`）+ 书架网格（`_cell`），搜索、排序弹窗、筛选、分页都在
- `manga_reader_page.dart`：横向 `PageView`（有 `PageController _pc`）+ 纵向 `ListView`（**没有 ScrollController**）；
  亮度/页间距在 `_settings`；`_onPage` 里已对横向下一页做 `precacheImage`
- 阅读位置 key：`lib/read_pos.dart:102` → `manga_pos_v2_<站>_<uid>_<目录>`，
  存 chapter_ref + page + total
- 详情页 `manga_detail_page.dart` 用 `manga_pos` 直接续到那一话

### 数据现状

- 21868 个目录 / 21872 个 `cover.webp`（含分卷残留），封面 28–29 KB 一张，原图宽约 300–800 px
- 热度：21868 本全部有值，中位 4245，最小 156，**没有 0 值**（"按热度排"后半段不是乱序）
- 同名 68 组 / 140 个目录，其中 19 组章节数相同、49 组不同

## 基线（三段都不许把它弄坏）

```bash
cd /vol1/1000/data/code/ongoing/openbbs
. /vol1/1000/data/code/.fenv
flutter analyze --no-pub          # 期望：No issues found!
flutter test --no-pub             # 期望：全过
```

依赖只准 `flutter pub get --offline`。在线 `pub get` 会失败并搅乱 lock。

后端改完必须重启并亲测，**按 pid 杀，别用 `pkill -f`**（2026-11-05 踩过，把执行命令的 shell 也杀了）：

```bash
pgrep -af "uvicorn app.main:app"
kill <pid>
cd /vol1/1000/data/code/ongoing/bbs/server && ./.venv/bin/python -m uvicorn app.main:app --host 0.0.0.0 --port 8080
```

## 三段总表

| 段 | 主题 | 后端动 | 前端动 | 报告 |
|---|---|---|---|---|
| 1 | 继续阅读 + 阅读器收尾 | 无（复用 `/history`） | `manga_tab.dart`、`manga_reader_page.dart`、`read_pos.dart` | `docs/manga/s1-resume.md` |
| 2 | 封面缩略图 + 书库巡检 + 同名区分 | 新增缩略图路由、`tools/` 两个脚本 | `manga.dart`、`manga_tab.dart`、`manga_detail_page.dart` | `docs/manga/s2-thumbs.md` |
| 3 | 离线下载 | `POST /history/batch` | `manga_download.dart`（新）、`downloads*.dart`、三处页面 | `docs/manga/s3-offline.md` |

---

# 第 1 段：继续阅读与阅读器收尾

## 角色

你是这个漫画区的读者代理。用户每天进来第一件事是找"我上次读到哪"，
现在这件事要三步：进漫画面 → 开排序菜单 → 选"阅读进度"。这段把这一步省掉。

## 范围

- 前端修改：`lib/pages/manga_tab.dart`、`lib/pages/manga_reader_page.dart`、`lib/read_pos.dart`
- 前端可能新增：`lib/widgets/continue_row.dart`（若 `manga_tab` 太挤）
- 后端：**不动**。`/history?limit=N` 现成，返回 `ref / title / cover / chapter / chapter_ref / page / total / viewed_at`

## 任务

### 1. 书架顶部「继续阅读」行

- 位置：`_recRow`（推荐横滑）**上方**，书架网格之上；只在 `_recs` 同屏时显示，进搜索态隐藏
- 数据：`GET /api/manga/history?limit=12`，前端过滤 `kind == 'local'`，取前 3–5 本
- 卡片：封面（40×56 圆角）+ 书名（1 行省略）+ `第N话 · 67%`；整行可点，**直接进阅读器并续到上次那一页**
- 空态：没读过任何书时整行不渲染，不留白
- 刷新：`_onBump()` 和下拉刷新时一起重取；失败**静默跳过**，不要为这一行弹错误条
- 不占用 `/shelf` 分页（不要为了这一行多打一次全量 shelf）

### 2. 纵向模式的阅读位置恢复

现在纵向 `ListView` 没有 `ScrollController`，退出再进从头开始。改：

- 给 `_scrollMode` 的 `ListView.builder` 挂 `ScrollController`
- 进入阅读器时若 `read_pos` 里有 `page` 且 `total > 1`：等首帧结束（`addPostFrameCallback`）
  后按 `page / (total-1) × maxScrollExtent` 滚到对应位置
- 滚动中继续走现有的 `_save(p)` 逻辑，**key 不变**（`manga_pos_v2_<站>_<uid>_<目录>`）
- 恢复只在"打开时"做一次，别在每次 `setState` 后重新定位

### 3. 跳页

- 顶部栏加页码按钮，显示 `12 / 45`，点击弹出跳转：横向用 `_pc.jumpToPage`，
  纵向按比例 `animateTo`（300 ms）
- 输入框只收数字，越界 clamp，不弹错误弹窗
- 键盘弹出时不要顶掉阅读器布局（`resizeToAvoidBottomInset: false` 已开就用现成的）

### 4. 读完一话的出口

- 横向：翻到最后一页时，底部浮一个「下一话」按钮（有下一话才显示），点了 `_gotoChapter(1)`
- 纵向：滚到 `maxScrollExtent` 附近（最后 200 px）时同样浮出
- 已经是最后一话：显示「已是最后一话」，点了回详情页
- 手动点过之后 2 秒内不再重复弹（避免抖）

## 验收

- 读到第 12 话第 7 页，退出再进，**横向和纵向都落在第 7 页**
- 换账号登录，两边的"继续阅读"互不串（key 带 uid 的老规矩）
- 跳页输入 999，落在最后一页，不崩
- 断网时打开漫画面，「继续阅读」行静默消失，不弹错误、书架照常走缓存
- `flutter analyze` 零问题，`flutter test` 全过

## 输出

`docs/manga/s1-resume.md`。提交 `manga/s1: 继续阅读与阅读器收尾`。

---

# 第 2 段：封面缩略图与书库巡检

## 角色

你是这个书库的库管。2 万本书，封面每张 28 KB 全量下发，巡检从来没做过。
这段把"看得快"和"心里有数"做出来。

## 范围

- 后端新增：`app/manga.py` 加 `GET /thumb/{dir}`（或独立静态目录，见任务 1）
- 脚本新增：`bbs/server/tools/make_thumbs.py`、`bbs/server/tools/check_library.py`
- 前端修改：`lib/manga.dart`（`MangaBook.coverUrl` 系列）、`manga_tab.dart`、`manga_detail_page.dart`、`zmh_book_page.dart`
- 磁盘新增：`/vol2/1000/manga/_thumb/`

## 任务

### 1. 封面缩略图

- 目标尺寸：宽 240 px，等比缩放，WebP 质量 80。预期 28 KB → 6–9 KB
- 落盘：`/vol2/1000/manga/_thumb/<目录名>.webp`，**文件名与目录名一一对应**（目录名含空格、符号，别改写成 id）
- `_thumb/` 是 `_scan()` 要忽略的目录（现在按 `_` 前缀跳过，确认这一点仍然成立）
- 生成脚本 `tools/make_thumbs.py`：
  - 遍历有 `meta.json` 的目录，`cover.webp` 存在且 `_thumb/<dir>.webp` 不存在或更旧才转
  - 并发 8，失败重试一次，结尾打印 `转了 N 张，跳过 M 张，失败 K 张`
  - **可重入**：中断后再跑只补缺的
- 服务端路由：`GET /api/manga/thumb/{dir}`，命中返回文件；文件不存在时
  **回落到原图 302**，不要 404（老数据、新抓的书都走这条路）
- 前端：列表卡片（`_cell`、`_recCell`、继续阅读行）用缩略图，详情页大图用原图。
  给 `MangaBook` 加 `coverThumb`（后端在 shelf 返回里加 `thumb` 字段，
  相对路径，前端 `url()` 补前缀，**别写死域名**）
- 缓存：缩略图 URL 也带 `?v=<mtime>`，换了封面能刷掉

### 2. 书库巡检脚本

`tools/check_library.py`，只读，不改盘。输出 `docs/manga/library-audit.md` + `library-audit.json`。

检查项（每项给出目录名清单，最多列 50 条 + 总数）：

| 项 | 判定 |
|---|---|
| 缺 meta | 有目录、有图、没 `meta.json` |
| 缺封面 | 没 `cover.webp` 或 < 1 KB |
| 空壳 | `meta.json` 的 `chapters` 为空 |
| 缺章节目录 | meta 里有、磁盘上没同名目录 |
| 缺图 | 章节目录里 `.jpg/.webp` 数为 0 |
| 坏图 | 小于 500 字节的图片 |
| 同名 | 68 组（已知，列出来供人工判断） |

- 全量跑一遍预计 1–3 分钟（2 万次 open + listdir），可接受；不要做增量
- 脚本输出到 stdout 的一行汇总要能直接贴给人看：
  `21868 本：缺 meta 0，缺封面 3，空壳 12，缺章节目录 41，缺图 7，坏图 19，同名 68 组`

### 3. 同名书在书架里区分

- 后端 `/shelf` 已返回 `authors`，前端不在列表显示
- 规则：同一个 `title` 在当前结果里出现两次及以上时，卡片标题下一行加作者名（小字、灰色、1 行省略）；
  唯一书名不加
- 实现放在 `_cell` 里，用「本页结果的 title 计数」判断，**不要为此加接口字段**
- 详情页顶部本来就有作者，不改

## 验收

- 用 21872 张封面跑一遍脚本，随机抽 10 张确认尺寸 240 宽、能打开
- 删掉某张缩略图，`/api/manga/thumb/<dir>` 回落原图，页面不裂
- 巡检脚本在**原库里只读**：跑完 `du -s --apparent-size /vol2/1000/manga` 前后值不变
- 书架滚动 100 本就停，抓包确认走的是缩略图（或看 Network 面板的文件大小）
- 同名书（如 `精灵幻想记` 两本）在书架里能看出作者不同
- `flutter analyze` 零问题，`flutter test` 全过

## 输出

`docs/manga/s2-thumbs.md` + `docs/manga/library-audit.md`。提交 `manga/s2: 缩略图与书库巡检`。

---

# 第 3 段：离线下载

**直接执行 `06-manga-3-stages.md` 第 3 段**，那段的设计仍然有效（落盘路径、索引格式、
两种任务粒度、本地优先取页、批量接口、下载中心接入）。不重复抄写，只列这三处差异：

1. 版本基线是 `1.1.5+100171`，不是 06 写的 `1.1.3+100169`
2. 书库 21868 本，"整本下载"要能中途取消，别一口气排 2 万本的队
3. 阅读位置 key 已是 `manga_pos_v2_<站>_<uid>_<目录>`，`manga_download` 的索引 key
   **另起一套**，不要复用位置 key

补充两条 06 没写、这次必须有的：

- 下载进度要能看见：书架卡片、下载中心两处都要有百分比，且**断点续传**（.part 文件，重连从断点接）
- 空间预检：开下之前算一遍总字节（页数 × 平均 300 KB），手机剩余空间不够时明确提示差多少，
  不要下到一半才报错

## 验收

沿用 06 第 3 段的验收项，再加：

- 下 20 话的过程中杀进程，重进能续，不从头来
- 空间不足时点"整本下载"直接拒绝，并说清需要多少、剩多少

## 输出

`docs/manga/s3-offline.md`。提交 `manga/s3: 离线下载与批量操作`。

---

## 公共约束（三段都适用）

- **老客户端的请求一个都不许坏。** 后端只加可选参数、加字段，现有字段名、类型、语义不变。
- 图片地址一律相对路径（`/manga/...`、`/manga_thumb/...`），前端用 `url()` 补前缀。
  落盘存相对路径，别写死域名。
- 平台分叉：`xxx_io.dart` / `xxx_web.dart` 成对，公共文件禁止 `dart:io`。
  web 端没有本地下载，`manga_download_web.dart` 直接返回"不支持"。
- 每段结束跑一遍 `analyze` + `test`，输出贴进报告。有失败先修，别往下走。
- 不改依赖版本，不跑在线 `pub get`。
- 真机验不过的，报告里写清哪条没验、为什么。

## 顺序与依赖

- 第 1 段纯前端，可先落，不依赖后端。
- 第 2 段的缩略图脚本会重写 `_thumb/`，跑之前在报告里记一次磁盘占用；巡检脚本要在缩略图**之后**跑，
  免得把 `_thumb` 当成缺封面。
- 第 3 段的下载进度要复用第 2 段的卡片布局，所以 2 先落。
- 三段都做完再跑一次全库 `analyze` + 一轮真机走查，然后按 `待修清单.md` 的规矩攒版本，不要一段一个包。
