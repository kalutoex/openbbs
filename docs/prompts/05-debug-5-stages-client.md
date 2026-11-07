# 客户端整体 Debug 提示词（五段 · 第二波）

写于 2026-11-08。范围只在前端：`/vol1/1000/data/code/ongoing/openbbs`（Flutter 客户端）。
后端 `bbs/server` 不在此轮范围内 —— 遇到疑似后端问题，记一条"疑似后端"附证据，不修、不深挖。

上一波（`04-debug-5-stages.md`，2026-11-05）是整项目五段，跑完修了 6 个 P 级问题。
这波不一样：11-05 之后客户端连推了 85 个提交，加了上传队列、前台服务、聊天、主题色、
M3 大屏、断网提示、阅读位置、撤回、分享等一大堆，**新代码比老代码更需要查**。
所以这波按"代码面"切，一段一个面，五段合起来覆盖全部 131 个 dart 文件。

盘面事实（2026-11-08 00:20 核对）：

- 版本 `1.5.33+143`，包名 `com.kalutoex.shijianxian`
- `lib/` 131 个 dart、37715 行。拆开：`lib/pages` 37 个 17961 行，`lib/widgets` 17 个 2662 行，
  `lib/*.dart` 顶层 72 个 7296 行，`lib/l10n` 生成文件 9796 行（**不读生成文件，只看 arb 与调用点**）
- 测试 23 个文件、96 个用例，全过
- 工具链 `/vol1/1000/data/code/sdks/flutter`，环境变量在 `/vol1/1000/data/code/.fenv`
- 平台分叉成对存在：`xxx_io.dart` / `xxx_web.dart`，公共文件禁止 `dart:io`

## 基线（这波开工前已达成，任何一段都不许把它弄坏）

```bash
cd /vol1/1000/data/code/ongoing/openbbs
. /vol1/1000/data/code/.fenv
flutter analyze --no-pub          # 期望：No issues found!
flutter test --no-pub             # 期望：+96: All tests passed!
```

依赖坑，照抄别改：

```bash
flutter pub get --offline         # 只准这一种
```

- 镜像 `pub.flutter-io.cn` 缺 `share_plus`，已手动把 `~/.pub-cache/hosted/pub.dev/share_plus-12.0.2`
  拷进 `~/.pub-cache/hosted/pub.flutter-io.cn/`。**在线 `pub get` 会失败并可能把 lock 搅乱，不要试。**
- `analyze` / `test` / `build` 一律带 `--no-pub`。
- 不要升降任何依赖版本来"顺手修好"，`dynamic_color` 当年就是 2.1.0 撞类型才锁到 1.7.0 的。

## 怎么用

五段各自独立，可以单独复制去跑，但顺序建议 1→2→3→4→5：

| 段 | 面 | 主要文件 | 报告 |
|---|---|---|---|
| 1 | 网络层与接口契约 | `api.dart`、`site_meta.dart`、`sites.dart`、`token_store.dart` | `docs/debug/r2-01-net-contract.md` |
| 2 | 状态、持久化、生命周期 | `store.dart`、`poller.dart`、各 `*_cache` / `local_files` / `draft_images` | `docs/debug/r2-02-state-store.md` |
| 3 | 文件链路（上传/下载/云盘） | `upload_manager.dart`、`cloud_page.dart`、`downloads*.dart`、`file_browser*.dart` | `docs/debug/r2-03-file-pipeline.md` |
| 4 | 页面与交互 | `lib/pages/*`（37 个）、`lib/widgets/*`（17 个）、`l10n` | `docs/debug/r2-04-pages-ux.md` |
| 5 | 主题、多端适配、发版收口 | `theme.dart`、`user_hue.dart`、`app_icon*`、`update*`、`release.sh` | `docs/debug/r2-05-theme-release.md` |

---

# 第 1 段：网络层与接口契约

## 角色

你是这个客户端的网络层排查者。目标不是重写 `api.dart`，是**找出会让用户看到错东西的错误**：
该换路没换、该超时没超时、该报 A 报成 B、该清的登录状态没清、字段少一个就崩。

## 范围

- `lib/api.dart`（768 行，全客户端的唯一出口）
- `lib/site_meta.dart`、`lib/site_config.dart`、`lib/sites.dart`、`lib/site_store.dart`
- `lib/token_store.dart`、`lib/cancel_token.dart`、`lib/l10n/error_text.dart`
- `lib/upload_progress.dart`（只查进度回调与错误传播，上传状态机归第 3 段）
- 测试：`test/api_failover_test.dart`、`test/api_idempotency_test.dart`、`test/api_timeout_test.dart`、
  `test/token_expiry_test.dart`、`test/site_meta_test.dart`、`test/site_catalog_test.dart`、`test/sites_test.dart`

不碰：页面布局（第 4 段）、文件落盘（第 3 段）、主题（第 5 段）。

## 前置动作

```bash
cd /vol1/1000/data/code/ongoing/openbbs
. /vol1/1000/data/code/.fenv
git rev-parse --short HEAD            # 记下开工点
flutter analyze --no-pub && flutter test --no-pub
```

四条测试文件先单独跑一遍，确认基线不是"刚好全过"：

```bash
flutter test --no-pub test/api_failover_test.dart test/api_idempotency_test.dart \
                test/api_timeout_test.dart test/token_expiry_test.dart
```

## 检查项（逐条给结论，不许跳过）

### 1. 出口选择与换路

- `setEndpoints`：去尾斜杠、去重、保持调用方顺序（v6 在前）。传空串、传 `https://` 裸协议头会怎样。
- `probe()` 串行、`probeAt` 的 3s / 10s 口径是否与注释一致；只认 200；返回 200 但 body 不是 JSON 算不算通。
- `probeReport` / `speedTest` 明确"不写 lastGood"，确认实现没写；站点管理页显示的 v6/v4 标记是否来自这两个。
- `_withFailover`：
  - `ApiException` 一律不换路 —— 服务端答了话就不是路的问题；确认换路中抛出 `ApiException` 时 `base` 被还原成 `prev`。
  - `retryOnTimeout: false` 只给流式上传；**全仓搜一遍还有哪些调用也传了 false，逐个判断对不对。**
  - 第二条路也超时之后的落点：`base` 停在哪？会不会一直停在一条死路上直到用户手动改站点？
  - `lastGood` / `onChannelChanged` 在换路成功与失败时各调一次还是两次。
  - 只有一条 endpoint 时（线上常见）这套逻辑是否变成无意义重试、翻倍超时。
- 首启无 endpoints（`base` 空）时，所有调用点会发出 `$base/api/...` 这种相对地址吗？在 web 上会打到当前域，在安卓上直接抛 —— 两边的界面表现各是什么。

### 2. 超时与幂等

- 把 `api.dart` 里所有 `.timeout(...)` 抄成一张表（行号 + 接口 + 秒数），逐条判断合不合理。
  已知：GET 类 15s、上传 60s、启动读 meta 6s、feed 探测 10s。有没有哪条读接口给了 60s（用户会以为卡死）。
- `X-Request-Id`：
  - 生成点在哪、格式是什么（长度、字符集）。
  - **同一个逻辑操作在换路重发、超时重发、用户手点重试时，是否复用同一个 id**——复用了才对。
  - 反过来：两次真的不同的发帖，会不会共用了一个 id（那就是丢帖）。
  - 服务端窗口 60 秒、客户端重试窗口多长，两者对不上会出现"重试变成第二条"。
- 写操作清单：把 `api.dart` 里所有 POST/PUT/DELETE/PATCH 方法列出来，逐个标"有 id / 无 id"。
  没有 id 的那些，重发会不会产生重复数据（关注、点赞、收藏、撤回、删除、改资料）。
- 幂等键在**跨进程**（杀进程重开）时还能不能续上，还是只在内存里活一次。

### 3. 鉴权与令牌

- 401 的处理链：`onUnauthorized` 有几个赋值点、会不会被覆盖成空；清 token 之后是否同时清
  `base` 缓存、用户信息、未读数、上传队列。
- 并发场景：首屏 5 个请求同时 401，是弹 5 次登录提示还是 1 次；有没有"清到一半又写回旧 token"。
- 改密码后旧 token 立刻失效 —— 客户端是否表现为"还在登录态但什么都打不开"。
- `token_store` 的 io / web 分叉：web 用 localStorage 时，隐私模式 / 配额满 / 多标签页互相覆盖 各自什么表现。
- 令牌里带密码版本号（服务端行为），客户端换密码成功后是否主动刷新本地 token，还是等下一次 401。

### 4. 错误映射与文案

- `ApiException.code` 只用于客户端自造错误、走 ARB；服务端 message 原文直显。确认没有把服务端 message
  也塞进 ARB 查表（会变成"键名当文案显示"）。
- `error_text.dart` 覆盖了哪些 code；全仓搜 `ApiException(` 的构造，找出没登记 code 的。
- 网络类异常（SocketException / TimeoutException / HandshakeException / ClientException）分别落到哪个文案。
  证书错误、DNS 解析失败、连接被拒，三种是不是都显示成"网络不给力"。
- 超时文案里有没有"稍后重试"这种空话（阿尔不喜欢小字说明，别加新解释文字）。
- 上传/下载错误是否把底层异常原文（`detail`）直接怼到界面。

### 5. 契约与解析容错

对着线上接口真跑一遍，逐字段对：

```bash
base=https://ipv6bbs.kalutoex.dpdns.org:26016
for p in /api/feed /api/meta /api/ui/config /api/cloud/usage /api/notify/poll; do
  echo "== $p"; curl -sk --max-time 8 "$base$p" | head -c 400; echo
done
```

- 列表字段缺省：`files: null`、`replies: []`、`user: {}` 三种输入下解析会不会抛。
- 数字字段来字符串（SQLite 的 `SUM` 回来可能是 null）：`size`、`quota`、`used`、`hue`、`count`。
- 时间字段：秒 / 毫秒 / ISO 字符串混用；`live_time.dart` 的输入口径。
- 未知字段：多出来的字段是否被静默忽略（应该是），有没有 `Map` 强转 `as Map<String, dynamic>` 直接崩。
- 分页：`has_more` / `next_offset` / 总数 三个口径，客户端用的是哪个；服务端某天只给一个时会不会死循环。
- 中文响应必须 `utf8.decode(bodyBytes)`；搜一遍有没有用 `r.body`（会按 latin1 解）。
- 站点自述回退链 `/.well-known/bbs.json` → `/api/meta`；两个都 404 时启动是否仍可用。

### 6. 多站与地址维护

- 站点切换时 `base` / `endpoints` / `token` / `lastGood` / 各站缓存 是否一起换；A 站的帖子会不会显示成 B 站的。
- 站点自述返回的 endpoints 比本地少时，是否只做并集不覆盖（1.4.1+87 修过一次，别回退）。
- `sites.dart` 里小站列表与屏蔽开关：屏蔽后是否还出现在 feed、目录、搜索结果里。

## 验证手段

- 换路：临时把 endpoints 改成 `['https://ipv6bbs.kalutoex.dpdns.org:26016','https://127.0.0.1:9']`，
  拔掉 v6 或改 hosts，观察是否落到第二条、界面提示条是否出现又收起。
- 超时：`iptables -I OUTPUT -p tcp --dport 26016 -j DROP`（记得 `-D` 撤掉），或用 `nc -l` 收下连接不回包。
- 幂等：同一 `X-Request-Id` 连发两次发帖请求到副本服务端，确认只多一条帖。
- 假服务端：写一个 40 行的 FastAPI/Flask stub 放 `/tmp/stub/`，按需返回畸形 JSON、缺字段、慢响应、401。
  **不要拿线上库做写测试**，写测试一律打副本（`127.0.0.1:18080`）或用测试号 30001–30050。

## 输出格式

写 `docs/debug/r2-01-net-contract.md`：

```
# 第 1 段报告：网络层与接口契约
时间 / 对象（commit）/ 方式 / 基线（analyze、test 结果）

## 一句话结论
## P0  （表格：编号 / 现象 / 证据 文件:行 / 影响面 / 建议修法）
## P1
## P2
## 待观察（有疑点但没证据，写清下一步怎么验证）
## 疑似后端（不修，只记）
## 本轮没查的（明确写出，别假装全覆盖）
```

## 硬约束

- 只改 `lib/` 下与本段相关的文件；**不改服务端**，不改 `lib/pages`。
- 不升级依赖、不重构、不 `dart format` 无关文件。
- 发现 P0/P1 先报结论和修法，等一句"修"再动手；P2 攒着一起说。
- 修完必须 `flutter analyze --no-pub` 0 issue、`flutter test --no-pub` 全过，并补一条对应回归测试。
- 公共约定见文末，同样适用。

---

# 第 2 段：状态、持久化与生命周期

## 角色

你是这个客户端的状态与本地存储排查者。目标：**找出会丢数据、会串账号、会在错误时间写盘的地方**。

## 范围

- `lib/store.dart`（967 行，`AppState` 单例）
- `lib/app_globals.dart`、`lib/accounts.dart`、`lib/site_store.dart`
- `lib/poller.dart`（246 行，轮询调度）、`lib/read_pos.dart`、`lib/draft_images*.dart`
- `lib/disk_cache*.dart`、`lib/img_cache*.dart`、`lib/img_size_store.dart`、`lib/cache_clear*.dart`
- `lib/local_files*.dart`、`lib/download_index.dart`（只查索引结构与一致性，下载流程归第 3 段）
- `lib/upload_manager.dart` 的 `_persist` / `_trim` / `init`（只查持久化，状态机归第 3 段）
- 测试：`test/accounts_test.dart`、`test/cloud_test.dart`、`test/download_index_test.dart`、`test/live_time_test.dart`

不碰：网络层（第 1 段）、页面布局（第 4 段）。

## 前置动作

```bash
cd /vol1/1000/data/code/ongoing/openbbs
. /vol1/1000/data/code/.fenv
git rev-parse --short HEAD
flutter test --no-pub test/accounts_test.dart test/cloud_test.dart test/download_index_test.dart
```

真机上先导出一份"现在的本地状态"作对照（安卓）：

```bash
adb shell run-as com.kalutoex.shijianxian ls -la files shared_prefs 2>/dev/null | head -40
```

## 检查项

### 1. `AppState` 的生命周期

- 全仓搜 `addListener(`，逐个确认有对应 `removeListener`，且不在 `dispose()` 之后的回调里 `setState`。
- `notifyListeners()` 的时机：有没有在一次用户操作里连发 5 次（列表整套重建）。
- 页面 `dispose` 后仍在跑的 `Future` / `Timer` / `StreamSubscription`：搜 `unawaited(`、`Timer(`、`.listen(`，
  逐个看有没有 `if (!mounted) return` 之外的取消逻辑。
- 单例在测试里怎么重置：`store` 泄漏会让测试之间互相污染（现在能过，是因为没人加新用例）。
- 冷启动顺序：`main.dart` 里 `init()` 与首帧的先后；有没有同步 IO 阻塞第一帧（读大 JSON、扫下载目录）。

### 2. 多账号与多站隔离

这是最容易串的地方，按矩阵查：

| 维度 | 切账号后应清 | 切站后应清 |
|---|---|---|
| 令牌 / 用户信息 | 清 | 清 |
| 未读数、通知游标 | 清 | 清 |
| 草稿（帖子、私信） | 清或隔离 | 隔离 |
| 阅读位置、历史 | 隔离 | 隔离 |
| 已下载、云盘缓存 | 隔离 | 隔离 |
| 主题色 hue、界面参数 | 随账号 | 随站 |
| 上传队列 | 隔离 | 隔离 |

- 逐项去代码里找 key，确认 key 里带了 uid / 站点 id。**没带 uid 的 key 全部列出来**，都是串账号隐患。
- 切账号的入口有几处（设置页退出、登录页换号、令牌失效被动登出、后台被踢），每处清的东西是否一致。
- 退出登录是否会主动清上传队列（不该清，任务可能还在跑）——判断并给出结论。

### 3. 持久化格式与容错

- 每个 key 的读写各在哪个文件；key 名有没有版本后缀。
- 读到的 JSON 损坏（截断、类型变了、被别的版本写过）时：抛异常、静默回默认值、还是把整个 store 搞挂。
  **这一条要在真机上验**：手动写坏一个 prefs 值再启动。
- 写盘时机：`read_pos` 在滚动时多久写一次（有没有节流到 1s 以上）；每写一次是否 `await` 到 UI 关键路径上。
- 原子写：写文件型存储（下载索引、草稿清单）是否 `tmp` + `rename`；断电/杀进程会不会留半截文件。
- 值的大小：有没有把整个列表（历史、下载索引、上传队列）每次全量写盘；列表涨到 1000 条时写一次多久。

### 4. 缓存与清理

- `img_cache` / `disk_cache` 的容量上限是多少、按什么淘汰（LRU？时间？）、上限是字节还是条数。
- `cache_clear` 清理时是否会删掉"正在被显示/正在下载"的文件；清完界面要不要重建。
- 磁盘满时的行为：写缓存失败是否静默；用户看到的是"图片一直转圈"还是"提示存储不足"。
- web 端：localStorage 5MB 限制、IndexedDB 是否被用；超限时抛的是什么，界面怎么表现。

### 5. 草稿与临时文件

- 草稿图片目录在哪（`draft_images*`），发帖成功后是否删除；取消发帖是否删；杀进程后残留多久。
- 草稿正文与图片的关系：先删图后发帖、图还在但正文清空，分别什么结果。
- 清理入口：设置页"清除缓存"会不会把草稿一起清掉（这会丢用户内容，属于 P1 起）。

### 6. 下载索引一致性

- 索引条目与磁盘真实文件的对应：索引有、文件没了（用户手动删）→ 打开时什么表现；
  文件在、索引没条（上次写入失败）→ 会不会重复下载、空间统计是否算错。
- 索引里的绝对路径在换设备 / 改存储目录 / SD 卡拔出后是否失效，失效后是否自动标记为"缺失"。
- 同一文件重复下载（不同帖、不同名字、同一 sha）是存两份还是一条，删除时是否互相影响。

### 7. 轮询与前后台

- `poller.dart` 的 `Timer`：`start` 被调两次会不会有两个定时器并行；`stop` 后是否真停。
- 退到后台（`AppLifecycleState.paused`）后是否停轮询；回前台是否立刻补一次（而不是等一个完整周期）。
- 轮询失败（断网）时的退避：现在是不是每次失败都按原间隔继续打（耗电、耗流量）。
- 轮询与 `netDown` 的关系：断网提示条出现后轮询是否还在跑。
- 通知权限被拒时，轮询是否白跑（还在拉数据但不显示）。

## 验证手段

- 单测：给每个"读损坏数据"的分支补一条测试（现在基本没有）。
- 真机：`adb shell run-as com.kalutoex.shijianxian cat shared_prefs/FlutterSharedPreferences.xml`，
  手动改一个值 → 强杀 → 重启，看是否白屏/回默认。
- 切账号：A 登录 → 进帖子页滑到一半 → 退出 → B 登录 → 回帖子页，看阅读位置/未读数/主题色是不是 A 的。
- 杀进程：上传中/草稿中/下载中 各杀一次，重启看队列与文件是否对得上。
- 磁盘：`adb shell df /data` 确认空间，再填满到 100MB 以内测一次上传与缓存。

## 输出格式

`docs/debug/r2-02-state-store.md`，格式同第 1 段。多一项：

```
## key 清单（key 名 / 存储位置 / 是否带 uid / 是否带站点 / 切账号是否清）
```

## 硬约束

- 不引入新依赖（尤其不要为了"状态管理"上 provider/riverpod，现在是 `ChangeNotifier`，保持）。
- 清缓存、清账号这类破坏性操作，写代码前先在真机上备份一份本地状态到自己电脑。
- 其它同第 1 段。

---

# 第 3 段：文件链路（上传 / 下载 / 云盘）

## 角色

你是这个客户端的文件链路排查者。这条链路上周刚出过三次事故：内置浏览器上传没进度、
退出页面丢任务、切后台断流。目标：**把"传不上去、传少了、传重了、看不见进度、切应用就断"
这一类问题一次查干净**。

## 范围

- `lib/upload_manager.dart`（388 行）、`lib/upload_progress.dart`、`lib/upload_keepalive*.dart`
- `lib/pages/cloud_page.dart`（1214 行）、`cloud_pick_page.dart`、`cloud_settings_page.dart`、
  `downloads_page.dart`（460 行）
- `lib/downloads*.dart`、`lib/download_index.dart`、`lib/file_browser*.dart`（694 行的 io 分叉）
- `lib/file_pick*.dart`、`lib/file_open*.dart`、`lib/permissions.dart`、`lib/img_compress.dart`
- `lib/widgets/file_card.dart`（466 行）
- `lib/api.dart` 中上传/分片/下载相关方法（只查这条链路，其它归第 1 段）
- 测试：`test/cloud_test.dart`、`test/download_index_test.dart`、`test/file_card_test.dart`

不碰：主题（第 5 段）、聊天页（第 4 段，只是共用 `file_card`）。

## 前置动作

```bash
cd /vol1/1000/data/code/ongoing/openbbs
. /vol1/1000/data/code/.fenv
git rev-parse --short HEAD
flutter test --no-pub test/cloud_test.dart test/download_index_test.dart test/file_card_test.dart
ls -la /vol3/1000/cloud/files | head     # 服务端文件根，只读看，不要动
```

准备三个样本：1MB 图片、100MB 普通文件、1.2GB 视频（额度 5120MB，注意别把测试号额度打满）。

## 检查项

### 1. 上传队列状态机

- `UploadJob` 的状态全集是什么（排队/上传中/成功/失败/取消/丢弃），有没有"卡在中间"的第四种状态。
- 并发度：一次拖 10 个文件进去，是串行还是并发；并发几个；服务端额度检查会不会被并发绕过（前端先算、后端也拦，两边都要有）。
- 重试：失败后自动重试几次、退避多久；`retry(job)` 手动重试是否复用同一个 job；重试到第 N 次后是否还留在队列里。
- 队列持久化：`_key='cloud_upload_queue'`、`_keep=30`。杀进程重开后：
  - "上传中"的任务恢复成什么状态（继续传、回到排队、直接失败）。
  - 已成功但被 `_trim` 裁掉的记录，界面上的"已传完"提示还在不在。
  - 队列里文件已被用户删掉的，恢复时怎么处理。
- 单例 `UploadManager.i` 在测试之间是否重置；`init()` 被调两次会不会读两遍队列。

### 2. 进度与速度

- 三条上传路径分别怎么报进度：内置浏览器 `<input type=file>`（web/XHR `upload.onprogress`）、
  系统选择器（流式字节计数）、图片选择器。
- 总进度聚合：多文件时进度条是"当前文件"还是"总字节"；总字节算法在文件大小未知时怎么算。
- 速度计算：滑动窗口多长；暂停/恢复后是否会算出"负数速度"或"爆表速度"。
- 进度回调频率：每 64KB 一次还是每字节一次（后者会卡 UI）。上传 1GB 时界面帧率。
- 完成后进度条是否停在 100% 然后消失；失败时进度条颜色/文案。

### 3. 前台服务与后台存活

- `upload_keepalive_io.dart`（35 行）：启动/停止时机；Android 14 的 `foregroundServiceType` 声明；
  Android 13+ `POST_NOTIFICATIONS` 被拒时服务还能不能起来。
- 上传中切后台、锁屏、上滑清后台（不清前台服务）、被厂商省电策略杀掉 —— 四种各测一次。
- 通知栏进度：更新频率、多文件时显示哪个、取消按钮是否真能取消。
- 服务被杀后队列状态是否停留在"上传中"（下次打开永远不动 = P1）。
- web 端对应的 `upload_keepalive_web.dart` 是不是空实现，空实现是否被正确调用（不要在 web 上调 Android API）。

### 4. 取消与中断

- 取消：`cancel(job)` 是否真断流（`CancelToken` 传到 http 层），还是只是停止更新 UI（后台继续传 = 流量事故，P1）。
- 取消后服务端残留的分片/临时文件由谁清；客户端有没有"清理残留"的调用。
- 上传中退出云盘页、切到别的 tab、退出登录，任务分别继续还是断。
- 网络从 WiFi 切 5G：是否触发重连；已传字节是否保留（断点续传）还是从头来。

### 5. 分片上传

- 分片大小、每片 offset 怎么算、`/file/chunk/done` 的幂等（服务端 60 秒窗口）。
- 弱网：某一片超时后重发的是同一片还是下一片；offset 错乱时服务端的报错客户端怎么处理。
- 1.2GB 视频：内存占用（有没有把整片读进内存再发）、耗时、失败率。
- 断点续传是否真的可用（选同一个文件继续），还是每次从 0 开始（现在"看着有进度"可能只是 UI）。

### 6. 下载

- 断点：中断后重下是续还是重来；服务端返回 206 时客户端是否正确 seek。
- 目标目录：Android 10+ 分区存储、`/storage/emulated/0/Download/` 写权限、SD 卡。
- 权限被拒：是否给"去设置"的入口（`permissions.dart`），返回后是否重试原操作。
- 重名：同名文件已存在是覆盖、加 `(1)`、还是失败。
- 下载中删除文件、删除任务、退出页面、杀进程，四种各测一次。
- 通知栏进度与取消，同上传。
- 空间不足时：下载前是否预检（`Content-Length` 与可用空间），还是下到一半才失败。

### 7. 文件打开与分享

- `file_open`：mime 猜错（无扩展名的 content-addressed 文件）、没有应用能打开、`content://` vs `file://`。
- 分享（`share_plus` 12.0.2）：分享大文件是否先复制到临时目录、临时文件是否清理。
- 已下载页"先定位再打开"在文件被移走后的表现。

### 8. 云盘界面

- 列表：分页、排序、大量文件（占位 1.4G 目录，看真实条数）时的滚动性能。
- 回收站：恢复、彻底删除、7 天自动清理的展示是否与后端一致；回收站文件占额度这件事界面上有没说清。
- 额度：用量显示与实际（`/api/cloud/usage`）对账；上传前预检 vs 传完才报满额。
- 空态、加载态、错误态三件套是否齐（云盘页现在没有 widget 测试，正好补）。

## 验证手段

- 真机必测：1MB / 100MB / 1.2GB 各一次；切后台、锁屏、清后台、飞行模式各一次。
- 断流验证：上传 100MB 到 40% 时开飞行模式 10 秒再恢复，看是否续上。
- 服务端视角对账：上传完成后在服务端 `user_files` / `files` 里查该用户条数与总字节，与客户端显示比。
- 内存：`adb shell dumpsys meminfo com.kalutoex.shijianxian | head -20`，上传 1.2GB 前后各一次。
- 日志：`adb logcat -s flutter`，确认看得到"开始/结束"分段日志（服务端 11-07 加的那条）。

## 输出格式

`docs/debug/r2-03-file-pipeline.md`，格式同第 1 段。多一张表：

```
## 上传三条路径对照（入口 / 有无字节进度 / 走不走 UploadManager / 有无前台服务 / 取消是否真断）
```

## 硬约束

- 测试上传只用测试号（30001–30050）或自己新注册的号，**不要用线上主账号把 5G 额度打满**。
- 测完把测试文件删干净（含回收站彻底删除），并在报告里写删了什么。
- 不改服务端、不改额度配置、不动 `/vol3/1000/cloud/files` 里的既有文件。
- 其它同第 1 段。

---

# 第 4 段：页面与交互

## 角色

你是这个客户端的界面排查者。目标：**找出用户真会碰到的界面错误** —— 白屏、错位、
点了没反应、转圈不停、返回键吃掉手势、切语言变英文、文字放大就溢出。不是审美意见，别写"我觉得这里不好看"。

## 范围

- `lib/pages/` 37 个文件 17961 行。优先级从高到低：
  `chat_page.dart` 2264、`thread_page.dart` 2117、`compose_page.dart` 1095、`user_page.dart` 744、
  `settings_page.dart` 707、`sites_page.dart` 662、`search_page.dart` 541、`edit_thread_page.dart` 526、
  `messages_page.dart` 486、`follow_page.dart` 478、`downloads_page.dart` 460、
  `home_page.dart` / `feed_tab.dart` / `me_tab.dart` / `thread_list_page.dart`
  其余页可以按同样清单抽查
- `lib/widgets/` 17 个 2662 行（`file_card` 已归第 3 段，其余都在这段）
- `lib/l10n/*.arb` 与 `l10n/error_text.dart`（**生成文件不读**）
- 测试：`test/compose_page_test.dart`、`test/smoke_test.dart`、`test/l10n_test.dart`、
  `test/locale_test.dart`、`test/net_down_test.dart`、`test/live_time_test.dart`、`test/theme_test.dart`（主题归第 5 段）

不碰：网络层、存储层、上传链路（前面三段）。

## 前置动作

```bash
cd /vol1/1000/data/code/ongoing/openbbs
. /vol1/1000/data/code/.fenv
git rev-parse --short HEAD
flutter test --no-pub
```

起一个能改代码的开发实例，同时开 web 端看大屏行为：

```bash
flutter run -d chrome --no-pub        # web
flutter run -d linux --no-pub         # 桌面（如果 build 支持）
```

## 检查项

### 1. 列表与分页（所有列表页通用）

- 触底加载：一次滚动会不会连发 3 次请求；已到最后一页还在请求吗。
- 到底部文案、加载中占位、失败重试入口 三件套是否都有（缺哪个列出来）。
- 下拉刷新与触底加载同时发生：会不会把新数据插到旧数据中间、出现重复条目。
- 切 tab / 返回再进：列表是保留还是重新拉；滚动位置是否保留（帖子页有阅读位置，其它页呢）。
- 空列表、只有一条、超过 200 条三种数据量下的滚动性能（`ListView.builder` 还是 `Column`）。
- 在请求未回来时退出页面：有没有 `setState() called after dispose`（开 `flutter run` 看控制台红字）。

### 2. 帖子页（`thread_page.dart` 2117 行）

- 楼层加载：首屏几楼、翻页、跳楼、回顶后是否重新拉。
- 长按菜单：复制、分享、撤回（两分钟内）、举报，各入口是否都在；两分钟的判断用客户端时间还是服务端时间（客户端改时间会怎样）。
- 撤回后列表是否原地更新，楼层号是否留空。
- 图片：点击进大图、转场、加载失败重试、保存、多图左右滑。
- 阅读位置恢复：退出再进是否回到原楼层；换设备/换账号是否误用别的位置。
- 翻页失败的重试按钮是否出现在正确位置（不是被底部输入框盖住）。
- 双击标题回顶与下拉刷新的手势冲突。

### 3. 聊天页（`chat_page.dart` 2264 行）

- 键盘：进入即贴底、输入时不被挡、点空白收键盘、表情面板与键盘切换后焦点是否回来（1.5.30+140 修过一次，别回退）。
- 长按气泡的横条菜单：贴边时会不会出屏、上下自动翻是否生效、按住回缩动画是否卡。
- 加载更早消息：滚到顶是否自动加载、加载时滚动位置是否跳动。
- 未读分割线：位置是否正确、已读后是否消失。
- 发送失败的消息：标红、可重发、重发后是否重复。
- 图片/文件消息：点击预览、保存、无应用可打开。
- 会话搜索：搜不到时的空态、清空后是否恢复。
- 表情面板：超出屏幕高度、横屏、输入法为第三方时的表现。

### 4. 发帖与编辑

- 草稿：退出是否提示、杀进程后是否恢复、图片是否随草稿。
- 附件：选完能否删、删了能否再选、总大小提示、上传失败后正文是否还在。
- 重复提交：连点两次发送、发送中再点、超时后重试（第 1 段查了协议，这里查界面是否给了重试入口且只发一次）。
- 图片压缩失败（`img_compress`）时是否静默丢图。
- 标题/正文长度超限的提示时机（输入时 vs 提交时）。
- 编辑已发帖：附件增删、删除后是否真的从帖子里消失。

### 5. 搜索、登录、我的

- 搜索：输入去抖、历史记录长按删、清空确认、结果为空与请求失败的区分。
- 登录：用户名/邮箱两种输入、密码小眼睛、自动填充、验证码倒计时、错误提示位置（不遮挡输入框）。
- 注册：邮箱格式、密码强度提示、协议/勾选项（如果有）。
- 我的/资料页：关注粉丝名单、资料公开开关、改资料、退出登录二次确认。
- 权限：普通用户能否点到管理页（admin_users / admin_reports / feature_requests_admin / ui_config_page），
  点进去是 403 文案还是白屏。

### 6. 全局交互

- Android 返回键：在嵌套弹层（sheet → dialog → 页面）里的关闭顺序是否合理；返回是否会退到已销毁的页面。
- SnackBar / Toast 重叠：连续操作时是否堆 5 条。
- 断网提示条（`netDown`）：出现/收起时机、遮挡底部输入框、点它有没有反应。
- 深链与通知点击：从通知进聊天/帖子，是否落到正确页并能返回。
- 冷启动：首屏连不上时的静默重试（1.5.21 加的），失败几次后给什么。

### 7. 无障碍与显示适配（只查会"坏"的）

- 系统字体放大到 2.0：主要 8 个页面逐个看有没有溢出（`RenderFlex overflow`）。
- 语义标签：图标按钮有没有 `tooltip`/`semanticLabel`（没有的列出来，别一个个补，先给数量）。
- 点击区小于 48dp 的控件清单。
- 深色模式下：图片遮罩、次要文字、分割线对比度是否够（具体到页面）。
- 横屏：手机横屏、平板横屏，主要 5 个页面的布局。

### 8. 多语言

- 硬编码中文残留：`grep -rnP '[\x{4e00}-\x{9fa5}]' lib/pages lib/widgets --include='*.dart'`，
  排除注释后逐条看（注释里的中文不算）。
- ARB 两语言键是否对称、占位符是否一致（`l10n_test` 覆盖多少）。
- 切系统语言后是否立刻生效（不重启）。
- 英文下长文案是否截断/溢出。

### 9. 错误态完整性（每个联网页面都要有）

对 8 个主页面各问一次：断网、超时、401、404、500、返回空，六种情况分别显示什么。
**判据：不许白屏、不许无限转圈、必须有重试入口、必须能退出去。**

## 验证手段

- `flutter run` 看控制台异常（红字全收，逐条归因）。
- 补 widget 测试 3 个（待修清单里的欠账）：帖子页分页、聊天页、云盘页。
- 真机走查按上面清单打勾，跳过项要写原因。
- 字体放大：`adb shell settings put system font_scale 2.0`（用完记得 `1.0`）。

## 输出格式

`docs/debug/r2-04-pages-ux.md`，格式同第 1 段。多一张：

```
## 页面矩阵（页面 / 空态 / 加载态 / 错误态 / 分页 / 返回键 / 字体 2.0 / 深色）
```

## 硬约束

- 界面改动**不调审美**：只修坏的（溢出、遮挡、白屏、转圈不停、点了没反应、文案错）。
  想改视觉的，写进"建议"，等阿尔点头。
- 不新增说明性小字（2026-11-06 删过 13 处，别又加回来）。
- 一次只改一个页面，改完 `flutter analyze --no-pub` 0 issue，再下一个。
- 其它同第 1 段。

---

# 第 5 段：主题、多端适配与发版收口

## 角色

你是收口的人。前面四段是找错，这一段是**把整个客户端打包成能发的东西**：主题不错乱、
大屏不散架、网页能构建、更新能装上、发出去的包能回滚。

## 范围

- `lib/theme.dart`（274 行）、`lib/user_hue.dart`、`lib/ui_config.dart`、`lib/pages/theme_color_page.dart`、
  `lib/pages/easter_egg_page.dart`、`lib/pages/ui_config_page.dart`、`lib/pages/about_page.dart`
- `lib/pages/home_page.dart`（大屏分级、NavigationRail）、`lib/widgets/page_width.dart`、`lib/widgets/app_sheet.dart`
- `lib/app_icon*.dart`、`lib/main.dart`（275 行）、`lib/update.dart`、`lib/update_prompt.dart`、
  `lib/share_out*.dart`、`lib/app_globals.dart`
- `android/`（`AndroidManifest.xml`、`build.gradle`、前台服务声明、图标别名）、`pubspec.yaml`
- `release.sh`、`deploy_web.sh`、`docs/DEPLOY.md`
- 测试：`test/theme_test.dart`、`test/start_tab_test.dart`、`test/update_test.dart`、`test/ui_config_test.dart`、
  `test/locale_test.dart`、`test/smoke_test.dart`

不碰：前三段的网络/存储/文件逻辑（发现越界问题只记不修）。

## 前置动作

```bash
cd /vol1/1000/data/code/ongoing/openbbs
. /vol1/1000/data/code/.fenv
git rev-parse --short HEAD
git tag "pre-r2-$(date +%Y%m%d-%H%M)"       # 收口前打点
flutter analyze --no-pub
flutter test --no-pub
```

## 检查项

### 1. 主题与配色

- 优先级链：`dynamic_color` 壁纸取色 → 用户自选 hue → 默认。逐条验证：
  - 开"壁纸取色"但系统不支持（Android 11 及以下、桌面、web）时是否静默回落。
  - 关掉壁纸取色后是否立刻回到自选 hue（不重启）。
  - 用户没设过 hue（新注册用户会自动分配随机 hue）时，本地存的默认值是 0 还是 null，
    0 会不会被当成"有效色相"导致所有人都是一个色。
- 关闭"卡片染色"后，哪些地方还在染色（1.5.22/1.5.29 改过两次，容易漏）。
- 深色模式：正文/次要文字/描边/图片遮罩/输入框填充 逐项看对比度；系统切换深浅是否即时。
- hue 随账号走：换账号后头像圈、楼层描边、私信气泡是否跟着换；换站是否跟着换。
- 主题色在 12 个限宽页面上是否一致（有的页面可能硬编码了颜色）。

### 2. 大屏与形态适配

- 840dp 断点：手机竖屏、手机横屏、平板竖、平板横、桌面窗口从 600 拖到 1400 —— 五种各看一次。
- NavigationRail：选中态、未读角标、切 tab 时内容页是否重建（状态丢失）。
- 双栏详情：左列表右详情时，返回键是关详情还是退页面；旋转屏幕后右栏内容是否丢。
- 限宽（`page_width.dart`）+ `showAppSheet` 收窄到 560：弹窗在超宽窗口下是否居中、遮罩是否全屏。
- 键盘弹出 + 双栏 + 聊天页 三者叠加时的高度计算（最易崩的组合）。

### 3. 多端分叉

- 公共文件里搜 `dart:io`：只允许出现在 `*_io.dart`。
- 每个 `xxx_io.dart` 都有 `xxx_web.dart`，反之亦然；两边对外 API 签名一致（否则会出现"web 上某功能静默失效"）。
- web 构建产物：`main.dart.js` 体积、canvaskit 是否漏了 skwasm/wimp/symbols（`deploy_web.sh` 有删除逻辑，手工构建时要照做）。
- service worker 必须是自毁版，否则老用户被旧缓存钉住（`deploy_web.sh` 里那段，别丢）。
- 桌面（Windows）构建能不能出包（`BUILD-WINDOWS.md` 的步骤现在是否还成立）。

### 4. 更新与图标

- `update.dart` 解析 `/api/app/latest`：channel、versionCode、downloadUrl、notes 缺字段时的降级。
- 覆盖安装：包名 `com.kalutoex.shijianxian`、签名一致、数据保留（登录态、已下载）。
- `release.sh stable|beta` 只搬包不改代码；`notes.txt` 与版本号一致（不一致用户看到旧文案）。
- 图标切换 8 套：Android 12+ 用别名；别名缺失时降级不崩（1.5.2–1.5.4 三个版本都栽在这）。

### 5. 构建与版本

- `flutter build apk --release --target-platform android-arm64 -PappId=com.kalutoex.shijianxian`
  能出包、体积正常（1.5.26 是 23.7MB 量级，明显变大要查是不是带了调试符号）。
- 版本号规则：**按 1.5.x 递增，不许跳 1.6.0**（阿尔明确要求过）。build number 单调递增。
- `pubspec.yaml`、`android/app/build.gradle`、关于页显示 三处版本号是否同源。
- 构建日志要真看（上次"打完包没看输出"导致以为卡住的教训）。

### 6. 线上回归（发版前必做一遍）

四个入口各一次：`ipv6bbs...:26016`、`ipv4bbs...:24016`、局域网 `192.168.1.212:8080`、web 版。
每个入口走一条最短路径：登录 → 发一帖（测试号）→ 回一楼 → 上传一张图 → 私信发一句 → 改密码 → 重新登录。
全部通过才算可发。

### 7. 回滚与备份

- 上一版 APK 在 `bbs/server/data/apk-archive/`，确认能找到上一版并说出回滚步骤（写进报告）。
- `deploy_web.sh` 部署前是否留旧 `main.dart.js` 备份（没有就补一条建议）。
- 本地状态升级：新版首次启动后，旧版本的本地缓存/草稿是否会丢（用旧版 APK 造数据 → 装新版 → 看）。

## 验证手段

```bash
flutter build apk --release --target-platform android-arm64 -PappId=com.kalutoex.shijianxian
flutter build web --release --base-href / --no-web-resources-cdn --pwa-strategy=none --no-pub
```

构建后按 `deploy_web.sh` 的三步手工核对（删 canvaskit 冗余、换自毁 SW、验首页与接口）。

## 输出格式

`docs/debug/r2-05-theme-release.md`，格式同第 1 段。多一节：

```
## 发版检查单（勾选项 + 实测结果 + 回滚步骤）
```

## 硬约束

- **不擅自发版**：能出包、能验，但推通道（`release.sh`）必须等阿尔说发。
- 不 bump 版本号除非同时在做发版；版本号不跳 1.6。
- 不改服务端配置、不动证书、不动 DDNS。
- 其它同第 1 段。

---

# 附：五段公共约定

**严重级别**

- `P0`：不能用、丢数据、串账号、越权、白屏。当场停手报给阿尔。
- `P1`：功能错但有绕路（重试能好、换个入口能好）。
- `P2`：体验、性能、文案、边角情况。

**证据要求**

每条结论必须给：`文件:行号`（或命令输出）、复现步骤、期望 vs 实际。
没有证据的怀疑写进"待观察"，不进 P 级清单。**"我觉得可能"这类句子一律不写。**

**动手节奏**

1. 先出报告，P0/P1 附建议修法，等一句"修"。
2. 修一条一个 commit，message 中文、说清修了什么。
3. 修完 `flutter analyze --no-pub` 必须 0 issue、`flutter test --no-pub` 必须全过，并补一条回归测试。
4. 修完不改版本号、不打包，等攒够一批再一起发。

**这轮别做的事**

- 不升级依赖、不换状态管理、不引入新包。
- 不为了"顺手"重构、不 `dart format` 无关文件、不改别人的注释风格。
- 不碰后端 `bbs/server`；疑似后端问题单独列一节。
- 不删测试用例让它"过"。

**每段报告最后都要写**

```
## 本轮没查的
```

老老实实列出跳过的文件和原因。五段拼起来才知道漏在哪。
