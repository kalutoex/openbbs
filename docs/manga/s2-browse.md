# 第 2 段 · 浏览与追更：排行榜、新话红点、阅读器偏好

做于 2026-11-16 21:40 – 22:30。范围按 `docs/prompts/06-manga-3-stages.md` 第 2 段。

## 改了什么

### 后端 `bbs/server/app/manga.py`

| 接口 | 改动 | 兼容性 |
|---|---|---|
| `GET /api/manga/rank` | 新增。`rank_type` = 0 人气 / 1 最新 / 2 好评，`page` 1–50 | 新接口 |
| `GET /api/manga/favs` | 每本多 `last_chapter`、`has_new` 两个字段 | 老字段原样，老客户端不认新字段也不受影响 |
| `POST /api/manga/fav/seen` | 新增。点开一本 = 新话看见了，把追更基线推到源站当前 | 新接口 |

`manga_favs` 加两列：`last_chapter`（上次核到的「最新」签名）、`checked_at`（上次核的时间）。
走 `EXTRA_COLUMNS` 自动补列，双进程（IPv4/IPv6 各一个）同时 ALTER 的冲突已经兜了。

**追更怎么算**，四条：

- 签名是 `"章节数|最新章节名"` 拼起来的字符串，不是只比章节名——源站有改名、合并卷的情况，只比名字会漏。
- 新收藏的 `last_chapter` 是空串：基线留到第一次核对立，否则「刚收藏就红点」。
- 每本半小时最多核一次（`CHECK_TTL = 1800`），一次请求最多核 8 本（`CHECK_PER_REQ = 8`），4 个并发（`CHECK_WORKERS = 4`），单本超时 12 秒。收藏 200 本也不会把 `/favs` 拖成十几秒——它每半小时只往前推 8 本，最久没核的先来。
- 核失败不改基线，只记 `checked_at`，不排队重试。源站抽风的时候宁可这次不报，也不要报错的红点。

`/fav/seen` 的基线由**服务端**算：客户端只报「我点开了这本」，不传最新章节。两边算的必须是同一套算法，否则客户端算出来的和存的字对不上，红点永远消不掉。

`/rank` 取不到源站时返回 `{"list": [], "error": true}`，不是 500：用户是主动点进来的，得能区分「源站挂了」和「这个榜本来就没书」。

### 前端

| 文件 | 改动 |
|---|---|
| `lib/pages/manga_rank_page.dart` | 新页。三个榜各一个 Tab，各榜独立滚动 + keepAlive；滑到底（`extentAfter < 600`）自动接下一页；按 id 去重（源站页间会重排）；中途失败给「重试」按钮而不是自动重试 |
| `lib/widgets/manga_card.dart` | 新组件。书架和榜单共用一套格子：封面、书名、底下一行小字、右上红点 |
| `lib/pages/manga_tab.dart` | 「推荐」右边加「更多 ›」进榜单；书架格子换成共用的 `MangaCoverCard` |
| `lib/pages/thread_list_page.dart` | 「我的 → 收藏」格子右上角红点，`has_new` 驱动 |
| `lib/pages/zmh_book_page.dart`、`source_book_page.dart` | 详情加载出来时如果是收藏着的，报一次 `fav/seen`，回来红点就没了 |
| `lib/manga_user.dart` | `MangaFav` 加 `lastChapter` / `hasNew`；新增 `MangaUserApi.markSeen` |
| `lib/store.dart` | 新增 `MangaPref`：横读/条漫、亮度、页间距，按「站点 + 账号」存 |
| `lib/pages/manga_reader_page.dart` | `initialVertical` 改可空（不传就用偏好）；亮度遮罩；页间距；底部设置面板 |

**阅读器偏好**为什么按账号分：上一版横读/条漫是页面里的临时状态，退出就丢；
要是改成全局一份，A 号在熄灯的房间把亮度调到 0.4，换个号登进来第一眼就是黑的。
key 是 `manga_read_<项>_<站点key>_u<uid>`，没登录用 `guest`。

亮度只压这一页（盖一层黑，**不改系统亮度**）——改系统亮度会影响别的 App，退出阅读器还得记得调回来，那是副作用不是功能。
遮罩只盖图，不盖上下两条工具条，不然调到暗处连按钮都找不着。
页间距只在条漫模式下有意义，横读时这一行不显示；最后一页下面不留空。

## 验证

后端（本机 26016 / 8080 两个口都对）：

- `/rank` 三个榜各 10 本；`rank_type=9` → 400；源站断网 → `error: true` 空列表。
- `/favs` 首次核 8 本，日志 `manga favs check: 8 books`；紧接着再请求核剩下 2 本。
- 收藏一本 → 改库里的 `last_chapter` 造出「有新话」→ `/favs` 返回 `has_new: true` → `/fav/seen` → `has_new: false`。
- 测试用的两条收藏（admin 名下）已删掉，uid 3 的那条 `last_chapter` 复原成空串。

前端：

- `flutter analyze`：No issues found。
- 新增 15 个测试（`test/manga_rank_test.dart` 8 个、`test/manga_pref_test.dart` 7 个），全套 132 个通过。
- 已出包 `1.1.4+100170` → `data/apk/stable/`，arm64，24.4MB，md5 `796e7689…a99`，notes 已补。
- web 已部署并复查：首页、`main.dart.js` 1.25MB(gz)、`/api/feed` 均正常。

## 没做的

- 红点只在「我的 → 收藏」显示。书架是本地库，没有追更概念；推荐位每次都是新书，标红点没意义。
- 红点不带「几话」数字，也不推送。打开收藏页才核，后台不轮询源站——漫画源站不稳定，按点巡检的成本比收益高。
- 榜单翻到第 50 页就停，再往后源站返回的是同一批书。
- 真机没验：亮度遮罩在 OLED 上的观感、条漫页间距在 1:2 长图上的效果，得手上过一遍。
