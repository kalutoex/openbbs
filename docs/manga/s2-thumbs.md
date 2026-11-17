# 第 2 段：封面缩略图、书库巡检、冷启动修复

2026-11-17。对应 `docs/prompts/07-manga-opt-3-stages.md` 第 2 段。

## 改了什么

| 文件 | 改动 |
|---|---|
| `bbs/server/tools/make_thumbs.py` | 新增。扫书库生成 240 宽 WebP |
| `bbs/server/tools/check_library.py` | 新增。只读书库体检，出 `library-audit.md` |
| `bbs/server/app/manga.py` | `/api/manga/thumb/{dir}` 路由；书条目加 `thumb`；冷启动修复 |
| `lib/manga.dart` | `thumb` 字段 + `coverThumb`（空则回落原图） |
| `lib/pages/manga_tab.dart` | 网格与「继续阅读」行改用缩略图 |

### 1. 缩略图

- 产物：`/vol2/1000/manga/_thumb/<目录名>.webp`，21872 张，240 宽、q80、method=6
- 路由：命中返回 200；没有缩略图的（新下的书还没跑脚本）302 回原图，列表不会裂
- 详情页、榜单页仍旧用原图，只有列表用小的

**实测收益没有预期大。** 抽样 15 本：

| | 平均大小 |
|---|---|
| 原图 `cover.webp` | 22.0 KB |
| 缩略图 | 18.4 KB |

只省 16%。原图本身就压得很小（先前估的 28 KB 偏高），所以字节上省得有限。
真正的收益是解码：240×320 的纹理对阵原图宽度，滚动时省的是内存和解码时间，不是带宽。

要再压可以 `QUALITY` 80 → 70，大约再省一成多，代价是观感。要不要压你说一句。

### 2. 冷启动空书架（不是本段计划内，撞见了）

现象：17:37 机器重启后，`/api/manga/shelf` 一直返回 `total 0`，App 里书架是空的。

根因两条叠在一起：

1. `_scan()` 首次没有数据时，调 `_refresh_books()` 后立刻 `return _cache["books"]`——还在空着。
   而 `_refresh_books()` 撞见 `busy` 会直接返回，于是并发请求全拿到空列表。
2. 机器刚起来页缓存是空的，4 个 uvicorn 各扫一遍 2 万目录，实测一次 **351.69 秒**
   （热的时候 1.5 秒）。这六分钟里，书架就是空的。

修法：

- 冷启动先用 `_scan_index.json` 顶上：内存里立刻有 21868 本，0.49 秒答完，后台线程再 stat 校正
- 索引也没有，才等扫描跑完（`threading.Event`，最长 300 秒），不再吐空书架
- 顺带：索引里的旧条目缺 `thumb` 字段时，按目录名现拼一个，不让前端回落原图

验证：重启后第一次 `shelf?limit=2` 用时 0.49s、`total 21868`、`thumb` 有值。

### 3. 巡检

见 `docs/manga/library-audit.md`。
`check_library.py` 里逐张图 `os.path.getsize` 改成 `os.scandir` 一次拿齐，
原来跑 4 分钟还在一万多本，改完一遍出结果。

## 测试

- `flutter analyze`：No issues found
- `flutter test`：133 个全过

## 回滚

- 缩略图是纯增量：删 `_thumb` 目录、删 `thumb` 字段，前端 `coverThumb` 自动回落原图
- 冷启动改动只在 `app/manga.py` 的 `_scan()` / `_refresh_books()`，回退这两处即可
