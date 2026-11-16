# 漫画区补全提示词（三段）

写于 2026-11-16 22:10。范围：`openbbs`（Flutter 客户端）+ `bbs/server`（FastAPI 后端）的漫画部分。

## 为什么有这份

2026-11-16 21:05，漫画库抓完了：4000 部、821 G、4047 个目录（47 个是分卷），
落在 `/vol2/1000/manga`。盘上还剩 2.8 T。

现在这套东西**能看，但不能管**。书架 4000 本只能一路往下滚，找不到、排不了、
不知道读到哪；连载书有没有新话，全靠肉眼盯着 `last_chapter` 那串字；
详情页写着"还没有下载任何一话"，可哪儿都没有下载按钮。

三段按"合起来才成立"切：书架（数据骨架）→ 浏览与阅读偏好 → 离线与批量。
每段都能单独跑，但建议 1→2→3，因为第 2 段的榜单页要复用第 1 段的书架卡片，
第 3 段的批量操作要复用第 2 段的阅读偏好存储。

## 盘面事实（2026-11-16 22:00 核对）

### 后端

- `bbs/server/app/manga.py`，370 行，13 个接口，全部挂在 `/api/manga` 前缀下：
  `GET /shelf`、`GET /detail/{dir}`、`GET /chapter/{dir}/{chapter_dir}`、
  `GET /fav/state`、`POST /fav`、`GET /favs`、
  `POST /history`、`GET /history`、`DELETE /history`、
  `GET /recommend`、`GET /zmh/search`、`GET /zmh/detail/{cid}`、`GET /zmh/pages/{cid}/{chid}`
- `bbs/server/app/zmh.py`，140 行，再漫画源站客户端：`rank(rank_type, page)`（自带 `_rank_cache`）、
  `search`、`detail`、`pages`
- 漫画不进数据库，是磁盘目录：

```
/vol2/1000/manga/<comic_id>_<书名>/meta.json      # 标题、作者、标签、简介、chapters[]
/vol2/1000/manga/<comic_id>_<书名>/cover.webp     # 封面，带 ?v=mtime
/vol2/1000/manga/<comic_id>_<书名>/<0001_第1话>/001.jpg
```

- 图片由 `main.py` 的静态挂载 `/manga` 直接发，不走接口
- `_scan()` 有 20 秒模块级缓存 `_cache`，**这份缓存与用户无关**
- 数据库已有两张表（`app/db.py` 271、282 行）：

```sql
manga_favs(uid, kind, ref, src, title, author, cover, created_at)     -- PK(uid,kind,ref)
manga_hist(uid, kind, ref, src, title, author, cover,
           chapter, chapter_ref, page, total, viewed_at)              -- idx(uid,viewed_at DESC)
```

`kind` 只认 `local`（磁盘目录名）/ `source`（书源 url）/ `zmh`（再漫画 cid）。

**注意：`manga_hist` 里已经有 `chapter`、`page`、`total` 三个字段，
阅读进度数据是齐的，只是 `shelf` 从来没把它 join 出来。**

### 客户端

版本 `1.1.3+100169`，`lib/` 里漫画相关的 10 个文件共 3135 行：

| 文件 | 行 | 内容 |
|---|---|---|
| `lib/pages/manga_tab.dart` | 430 | 漫画面：推荐横滑 + 书架网格 |
| `lib/pages/manga_detail_page.dart` | 457 | 本地书详情：收藏、简介、章节表 |
| `lib/pages/manga_reader_page.dart` | 421 | 阅读器：横向翻页 / 纵向连续、双击缩放 |
| `lib/pages/zmh_book_page.dart` | 395 | 再漫画书详情（外部源） |
| `lib/pages/source_book_page.dart` | 400 | 书源书详情 |
| `lib/pages/source_search_page.dart` | 291 | 书源搜索 |
| `lib/manga.dart` | 164 | `MangaBook` / `MangaShelfPage` 模型与接口 |
| `lib/manga_user.dart` | 242 | 收藏、历史、`ReadRef`、`markRead` |
| `lib/zmh.dart` | 147 | 再漫画接口封装 |
| `lib/manga_source.dart` | 188 | 书源接口封装 |

已知的三个硬伤（本文件三段要解决的就是它们）：

1. `MangaBook` 只有 `id/dir/title/authors/types/status/desc/cover/chapterCount/lastChapter`，
   **没有进度字段**。后端 `_scan()` 明明算了 `updated`，前端也没接。
2. `manga_reader_page.dart:34` 的 `initialVertical` 默认 `false`，详情页 `_open()` 不传参，
   书源页 `zmh_book_page.dart:93`、`source_book_page.dart:95` 硬编码 `true`。
   **切换只在内存里，退出就回默认。**
3. `manga_detail_page.dart` 里 `'$n 话已下载'` 是纯展示，`DownloadManager.start`
   只服务论坛附件，**漫画没有任何下载入口**。

## 基线（三段都不许把它弄坏）

```bash
cd /vol1/1000/data/code/ongoing/openbbs
. /vol1/1000/data/code/.fenv
flutter analyze --no-pub          # 期望：No issues found!
flutter test --no-pub             # 期望：+26 文件全过
```

依赖只准这样装：

```bash
flutter pub get --offline
```

在线 `pub get` 会失败并可能搅乱 lock（镜像缺 `share_plus`，已手动拷进 pub-cache）。

后端改完必须重启并亲测：

```bash
# 先看当前是谁在跑，按 pid 杀，别用 pkill -f（2026-11-05 踩过一次，把执行命令的 shell 也杀了）
pgrep -af "uvicorn app.main:app"
kill <pid>
cd /vol1/1000/data/code/ongoing/bbs/server && ./.venv/bin/python -m uvicorn app.main:app --host 0.0.0.0 --port 8080
```

改完接口，用 admin 的 token 真打一遍，别只看代码。

## 三段总表

| 段 | 主题 | 后端动 | 前端动 | 报告 |
|---|---|---|---|---|
| 1 | 书架：排序、筛选、搜索、进度 | `manga.py` 的 `/shelf`、`/detail` | `manga_tab.dart`、`manga.dart`、`manga_detail_page.dart` | `docs/manga/s1-shelf.md` |
| 2 | 浏览、追更、阅读偏好 | 新增 `/rank`、`/tags`、`/favs` 加 `has_new` | `manga_rank_page.dart`（新）、`manga_reader_page.dart`、`store.dart` | `docs/manga/s2-browse.md` |
| 3 | 离线下载、批量操作 | 新增 `/history/batch` | `manga_download.dart`（新）、`downloads*.dart`、三处页面多选 | `docs/manga/s3-offline.md` |

---

# 第 1 段：书架

## 角色

你是这个书架的管理员。目标不是把书摆好看，是让 4000 本**找得到、排得动、知进度**。

现在用户打开漫画面，只能顺着"最近抓取"一路往下滚。想找《花薰凛然》，得滚四千格；
想看上次读到哪，得点进去才知道。这段全部在补这个。

## 范围

- 后端：`bbs/server/app/manga.py` 的 `/shelf`（101 行起）与 `/detail/{dir}`（117 行起）
- 前端：`lib/pages/manga_tab.dart`、`lib/manga.dart`、`lib/pages/manga_detail_page.dart`
- 测试：新增 `test/manga_shelf_test.dart`

不碰：阅读器内部（第 2 段）、下载（第 3 段）、收藏历史页。

## 前置动作

```bash
cd /vol1/1000/data/code/ongoing/openbbs
. /vol1/1000/data/code/.fenv
git rev-parse --short HEAD
flutter analyze --no-pub && flutter test --no-pub
curl -s "http://127.0.0.1:8080/api/manga/shelf?limit=2" | head -40   # 记下现在的返回形状
```

## 任务

### 1. `/shelf` 加三个可选参数（不改默认行为）

```python
@router.get("/shelf")
def shelf(offset: int = 0, limit: int = 0,
          sort: str = "recent", status: str = "", q: str = "",
          user=Depends(optional_user), c=Depends(get_conn)):
```

- `sort`：`recent`（默认，等价现在的 `-updated`）/ `title`（书名 `title` 排序，中文按 Unicode）/ `progress`（最近阅读靠前，没读过的垫底）
- `status`：空 = 全部；否则按 `status` 字段子串过滤（值是"连载中"/"已完结"这种中文，`_tags()` 出来是逗号拼接）
- `q`：书名 / 作者 / 标签模糊匹配。**本地库在内存里筛就够了**——`_scan()` 已经有 20 秒缓存，4000 条一次 `in` 判断是微秒级，不要为这个上全文索引
- 老调用方（不带任何新参数）返回必须和现在**逐字节一致**，`total` 语义不变（筛选后的总数）

### 2. `/shelf` 与 `/detail` 加 `progress`

```json
"progress": {"chapter": "第12话", "chapter_dir": "0012_第12话", "page": 5,
             "total": 18, "percent": 0.31, "viewed_at": 1763300000}
```

- 数据来自 `manga_hist`：`WHERE uid=? AND kind='local' AND ref=<book.dir>`
- **必须按请求用户实时查，绝对不能塞进 `_scan()` 的模块缓存**——那份缓存跨用户共用，塞进去就是串号（第二批 debug 里已经出过一次同类问题）
- 未登录（`user is None`）时不返回该字段，前端按"未读"处理
- `page/total` 是页级进度，`percent` 用 `(page+1)/total` 更贴近"看完"的直觉，`total=0` 时给 0
- 一次查 12 本，**不要写成循环里 12 次单查**，用一条 `IN (...)` 取回来再在 Python 里映射

### 3. 前端书架

- AppBar 加一个排序菜单（`PopupMenuButton`，三项：最近更新 / 书名 / 阅读进度），当前项打勾
- 书架标题行右侧加状态筛选（`FilterChip`：全部 / 连载中 / 已完结），单选
- 把现在跳外部搜索的放大镜**保留**，另在书架标题行加一个书架内搜索入口，
  或者顶部直接放一个可展开的搜索框——搜的是本地 4000 本，不跳页
- 排序 / 筛选 / 搜索任一变化：**offset 归零，已加载列表清空，重新拉第一页**。
  现在的滚动分页逻辑（`hasMore`）不能破
- 卡片在书名下面那行显示进度：有进度写"第12话 · 31%"，无进度写"未读"，
  现在那行显示的是 `lastChapter`（最新话），**两者不要混**：最新话是"更新到哪"，进度是"你读到哪"

### 4. 详情页

- 顶部"从头看"那颗按钮旁边，有进度时再加一颗"继续看"（跳到 `progress.chapter_dir` 对应下标）
- 章节表里，已读过的章节名后面加个小勾或把颜色压暗

## 验收

- `curl "…/shelf?sort=title&limit=5"`、`?q=花薰`、`?status=连载中` 各返回正确，`total` 对
- 登录用户拿到的 `progress` 与 `manga_hist` 里那行一致；换个账号拿到的不同
- 不带参数的老请求返回与改前 diff 为空（除新增 `progress` 字段）
- 4000 本切排序、切筛选，界面 1 秒内有反应（吃 `_scan` 缓存）
- `flutter analyze` 零问题，`flutter test` 全过且新增用例覆盖：`MangaShelfPage` 解析新字段、参数拼装、`percent` 边界（`total=0`）

## 输出

`docs/manga/s1-shelf.md`：改了哪些文件、接口 diff、一个"改前/改后"的返回样例、
自己踩到的坑。提交一次，commit message 用 `manga/s1: 书架排序筛选搜索与进度`。

---

# 第 2 段：浏览、追更、阅读偏好

## 角色

你是这个漫画区的门面。用户现在只有首页那 18 本推荐横滑，
而池子里躺着 44757 部。这段要给他入口，还要让"追的书有没有新话"这件事自己浮出来。

## 范围

- 后端：`manga.py` 新增 `/rank`、`/tags`；`/favs`（259 行）加 `has_new`；`db.py` 加列迁移
- 前端：新增 `lib/pages/manga_rank_page.dart`；`lib/zmh.dart`；`lib/pages/manga_reader_page.dart`；`lib/store.dart`
- 测试：新增 `test/manga_rank_test.dart`、`test/manga_pref_test.dart`

不碰：书架（第 1 段）、下载（第 3 段）。

## 任务

### 1. 榜单页（后端代理 + 前端新页）

`zmh.rank(rank_type, page)` 已经自带缓存（`_rank_cache` + `RANK_TTL`），直接调：

```python
@router.get("/rank")
async def rank(rank_type: str = "0", page: int = 1, user=Depends(optional_user)):
    """0=人气 1=最新 2=好评。源站挂了返回空列表，前端显示重试，不要 500。"""
```

- 返回 `{"type": ..., "page": ..., "list": [...]}`，`list` 元素与 `/zmh/search` 同形状
- `rank_type` 白名单校验（只认 `0/1/2`），其余返回 400
- 前端 `manga_rank_page.dart`：顶部三个 tab（人气 / 最新 / 好评），网格 + 上拉翻页，
  卡片复用书架卡片（抽成公共 widget，别抄一份），点击进 `zmh_book_page`
- 入口：漫画面推荐横滑右侧加"更多 ›"，点进榜单页

### 2. 追更

`manga_favs` 加两列（`db.py` 里写迁移，SQLite 加列要先查 `PRAGMA table_info`，重复执行不能报错）：

```sql
ALTER TABLE manga_favs ADD COLUMN last_chapter TEXT NOT NULL DEFAULT '';
ALTER TABLE manga_favs ADD COLUMN checked_at INTEGER NOT NULL DEFAULT 0;
```

- 收藏时把当时的"最新章节名"写进 `last_chapter`
- `GET /api/manga/favs` 返回每项加 `has_new`：`true` = 源站最新章节与 `last_chapter` 不同
- 检查策略要克制：
  - 只查 `kind in ('zmh','source')`，本地书不查（本地库是我们自己的快照，不会自己变）
  - `checked_at` 距今 30 分钟内不重复查
  - **一次请求最多检查 8 本**，剩下的保持 `checked_at=0`，下次请求接着查——
    别一次拉 50 本去打源站，那个站经不起
  - 单本失败不影响响应，该本 `has_new=false`，`checked_at` 记上（免得一直重试）
- 前端：收藏页 / 漫画面书架卡片右上角红点

### 3. 阅读偏好持久化

- `lib/store.dart` 加三项，**key 必须带账号与站点作用域**
  （第二批 debug 的 P1 就是 key 不带作用域，换号串数据；别重犯）：

```
manga.read.vertical.<站点hash>.<uid>
manga.read.brightness.<站点hash>.<uid>
manga.read.gap.<站点hash>.<uid>
```

- 阅读器启动从 store 读，切换时写回；`initialVertical` 保留但改成"显式传参优先，否则读 store"
- 详情页 `_open()` 不再依赖默认值；`zmh_book_page.dart:93`、`source_book_page.dart:95`
  的硬编码 `true` 改成走同一套
- 阅读器工具栏加亮度滑条（0.3–1.0，暗到不影响熄灯看），只作用于本页遮罩，不改系统亮度

## 验收

- 榜单三个 tab 都能翻到第 3 页，源站断开时显示"重试"而不是白屏
- 收藏一本连载书，手动改库里的 `last_chapter` 再拉 `/favs`，`has_new` 变 `true`
- 收藏 30 本，一次 `/favs` 请求里源站调用不超过 8 次（看日志计数）
- 阅读器横竖切换后退出重进，保持上次选择；换账号登录后是默认值（不串）
- `flutter analyze` 零问题，`flutter test` 全过

## 输出

`docs/manga/s2-browse.md`。提交 `manga/s2: 榜单页、追更红点与阅读偏好`。

---

# 第 3 段：离线与批量

## 角色

你是这个漫画区的搬运工。服务器上有 821 G，手机上一张都没有；
用户在地铁里、在没网的地方，现在打开就是一片裂图。这段把"能带走"做出来。

## 范围

- 前端新增：`lib/manga_download.dart`（+ `_io` / `_web` 分叉，若需要）
- 前端修改：`manga_detail_page.dart`、`manga_tab.dart`、`manga_reader_page.dart`、`downloads*.dart`
- 后端：新增 `POST /api/manga/history/batch`（批量标记已读）
- 测试：新增 `test/manga_download_test.dart`

## 任务

### 1. 本地书的离线下载（主体）

- 落盘位置：`<appSupport>/manga/<站点hash>/<dir>/<chapter_dir>/001.webp`，
  与现有 `disk_cache` 分开（那个会被"清除缓存"清掉，下的书不该被清）
- 一个索引：`<appSupport>/manga/<站点hash>/index.json`，记每本书已完成的话、
  每话的页数、总字节、下载时间。**读索引用现有 `download_index.dart` 那套，
  不要新造一个格式**
- 任务粒度有两种，都要：
  - 单话：详情页章节行右侧一个下载图标
  - 整本未读：详情页底部"下载未读（N 话）"
- 并发 2，串行取图，失败重试 2 次（间隔 1s / 3s），单话失败不中断整本，结尾报"3 话失败"
- 阅读器取页顺序：**本地 → 网络**。本地命中直接给 `Image.file`，
  网络回落保持现在逻辑。切话时若下一话已缓存，提示"已离线"
- 下载中的书在书架卡片上一个小进度条；下完显示"离线"

### 2. 下载中心接入

`downloads*.dart` 现在只管论坛附件。加一类"漫画"任务，显示书名 + 话数 + 进度，
支持暂停 / 取消 / 删除本地文件。删除只删 `<appSupport>/manga/...` 下的东西，**别的目录一根手指都不许碰**。

### 3. 批量操作

- 书架长按进入多选：勾选多本后底栏出现「批量下载 / 标记已读 / 删除离线」
- 详情页章节表长按进入多选：批量下载 / 批量标记已读
- 批量标记已读走后端新接口，一次请求一个 `refs[]` 数组，**别循环调 `markRead` 一百次**：

```python
@router.post("/history/batch")
def mark_read_batch(p: dict = Body(...), user=Depends(require_user), c=Depends(get_conn)):
    """p = {"kind":"local","refs":[...]}, 最多 200 条。返回 {"ok": n}"""
```

- 批量操作都要有取消，不阻塞界面

## 验收

- 下载一话后断网，重进阅读器能看（真断网测，不是改 flag）
- 索引文件损坏（手动写坏 JSON）后重进不崩，提示重新下载
- 删一本书的离线文件后，磁盘上只剩别的书（用 `du -sh` 前后对比）
- 批量标记 100 本，只发 1 次请求
- `flutter analyze` 零问题，`flutter test` 全过

## 输出

`docs/manga/s3-offline.md`。提交 `manga/s3: 离线下载与批量操作`。

---

## 公共约束（三段都适用）

- **老客户端的请求一个都不许坏。** 所有后端改动只能是"加可选参数 / 加字段"，
  现有字段的名字、类型、语义全部保持。
- 接口返回的图片地址是 `/manga/...` 相对路径，前端用 `url()` 补站点前缀——
  第 3 段落盘时要存**相对路径**，别把带域名的绝对地址写进索引（换站点就全废）。
- 平台分叉：`xxx_io.dart` / `xxx_web.dart` 成对出现，公共文件禁止 `dart:io`。
  web 端没有"下载到本地"这个概念，`manga_download_web.dart` 直接返回"不支持"，
  不要为了统一接口硬造浏览器的假下载。
- 每段结束跑一遍全套 `analyze` + `test`，把输出贴进报告。有失败先修，别往下走。
- 不要顺手改依赖版本、不要 `flutter pub get`（在线）。
- 真机/模拟器验不过的，报告里写清楚哪一条没验、为什么。

## 顺序与依赖

- 第 2 段的榜单页要复用第 1 段抽出来的书架卡片 widget，所以 1 先落。
- 第 3 段的批量"标记已读"要读第 2 段存的阅读偏好做默认值，所以 2 先落。
- 三段都做完，再跑一次全库 `flutter analyze` + 一轮真机走查，
  然后按 `待修清单.md` 的规矩攒版本，不要一段一个包。
