# openbbs · 五段实施计划

> 目标形态：一个主站 + 若干独立小站。注册登录只在主站，小站能离线验签、被封全网生效。

---

## 前置约束

**C3（token 不过期）+ 封号口径，两者必须有黑名单同步来兜底。**

token 永不过期，就没法靠过期让封号生效，只能在接口层拦。所以第 2 段把
"主站维护全局黑名单、小站定时拉"写成强制项，不是可选项。

---

## 第 1 段 · 数据模型与命名

**目标**：把"板块"从数据层和文案层彻底拿掉，改成一站一层。

**已定**：A1 独立实例、F1 主站分配 id、N 主站叫"站"小站叫"XX站"、小站不能开小小站。

**做**

- 后端删掉板块层（`forums` 表/字段/接口），帖子直属站点
- 客户端删板块列表页，首页 = 站点列表 + 帖子流
- 全量文案：`XX吧` → `XX站`，`板块` → `站`
- 站点表加 `site_id`，由主站登记下发

**验收**：库里搜不到板块表；代码里没有 forum 这个概念；文案零残留；`flutter analyze` 零 error。

**不做**：不碰鉴权、不碰网络层、不碰部署。

---

## 第 2 段 · 身份与鉴权

**目标**：注册登录只在主站，小站离线验签，封号全网生效。

**已定**：B1 公钥离线验签、C3 token 不过期、M1 小站不放注册、E1 只存 uid、D 封号后读写全禁并明确告知。

**做**

- 主站签发 JWT，公钥随 `/meta` 下发；小站只验签，不联网
- 主站维护全局黑名单，`/blacklist?since=` 返回 `{uid, ts}` + 主站签名
- 小站每 60 秒拉一次，落地本地表
- 命中黑名单：所有接口（含读接口）返回 403，固定文案"账号已被封禁"
- 用户资料只存 uid，展示时按主站地址取

**验收**：主站封号后 60 秒内，该账号在所有小站读写全部 403；小站断外网仍能验已签发 token。

**不做**：不做 refresh、不做小站本地账号。

---

## 第 3 段 · 协议与站点清单

**目标**：让小站能自描述，客户端能自动识别。

**已定**：I1 `/meta` 报版本+能力位、H1 包内种子 + 手动导入、F1 主站登记。

**做**

- `/meta` 返回 `{api, site_id, name, capabilities[]}`
- `/.well-known/bbs.json` 按 `docs/bbs.json.example`，单站自述 `sites` 留一条
- 主站提供登记接口与目录，分配 `site_id`，查重
- 客户端按 `api` 版本开关功能，不支持就标"需更新客户端"

**验收**：新站部署后填域名即可被识别；清单三条校验规则（id 去重、缺地址丢弃、版本过高禁入）都生效。

**不做**：不做站点自动发现、不做搜索聚合。

---

## 第 4 段 · 客户端

**目标**：一个入口管多个站，自动选路，状态透明。

**已定**：H1、J2 各站自定义端口、E1、M1。

**做**

- 站点管理页：添加、删除、扫 JSON 导入（一个文件多个站）
- 每站存 `endpoints` 列表，启动时 v6 优先、失败按顺序回落
- 同 `site_id` 去重；连不上的站标灰，不弹窗骂人
- 被封 403 时全应用只显示封禁页
- 登录统一跳主站，token 全局共用

**验收**：无网启动不崩；多个站切换不需要重登；封禁账号点任何页面都出封禁提示。

**不做**：不做刷新、不做离线缓存帖子。

---

## 第 5 段 · 部署包与运维

**目标**：小站长填完数据就能起站。

**已定**：K3 Docker + tar 双形态、L3 不自动升级、O1 每日快照、J2 端口自定。

**做**

- Dockerfile + compose，卷挂 `data/`
- `install.sh`：检依赖、生成 secret、建库、打印管理员码
- `site.json` 收全部参数：站名、`site_id`、端口、证书、主站地址、公钥
- 每日 SQLite 快照，保留可配份数，一键恢复命令
- 只打印"有新版本"，不自动升

**验收**：空机器 10 分钟内起站；改端口只动 `site.json`；备份能直接恢复出可跑实例。

**不做**：不做自动升级、不做主站代管数据。

---

## 进度

| 段 | 状态 | 备注 |
|---|---|---|
| 1 数据模型与命名 | 完成 | 提交 `1d9f1c6` 去掉板块这一层 |
| 2 身份与鉴权 | 完成（资料拉取待补） | Ed25519 JWT、`/meta` 发公钥、黑名单签名增量；实测封禁 54 秒、解封 48 秒生效；断网仍可验签 |
| 3 协议与站点清单 | 完成 | `api` 升到 2；`/meta` 补全自述；`/.well-known/bbs.json`；主站目录 + 登记 + 查重；小站自动登记；三条校验在前后端各一份 |
| 4 客户端 | 完成 | 站点表 `sites_v1`；每站多入口、v6 优先按序回落；站点管理页（加/删/切/设登录站/粘贴清单/拉主站目录）；403 封禁切整页；`analyze` 0 error、51 项测试全绿 |
| 5 部署包与运维 | 完成 | 三形态（直跑 / Docker / tar）；端口、证书、备份份数只在 `site.json`；备份精确到秒、恢复先留底；`check_update.sh` 只提示不升级。本机 docker 无权限，镜像未实构建 |
| 6 搜索与内容安全 | 完成 | 帖子/回复两份 FTS5 索引（trigram）、`/search` 加 `kind`/`sort` 三段返回；敏感词表 + 图片黑名单 + 算术挑战题；客户端搜索页三段 chip、历史词；`analyze` 0 error、68 项测试全绿；服务端 39 项接口验收全过 |
| 7 私信与异地备份 | 完成 | 私信会话/消息两表 + 6 个接口（全挂 `require_user`）；客户端私信列表与对话页、抽屉/主页/消息页三个入口、未读合并进"消息"角标；备份读 `site.json` 并做镜像 + sha256 校验，`restore.sh --from-mirror` |

### 第 2 段落地细节

- **token**：EdDSA(Ed25519) JWT，payload 只有 `uid` + `iat` + 可选 `iss`，**没有 exp**（C3）。
  老格式 `uid:ts:sig` 仍可解码，平滑过渡；新签发一律 JWT。
- **密钥**：`data/jwt_key`（32 字节裸私钥，0600，首次启动生成，永不复写）。
  公钥由私钥派生，走 `/meta` 和 `/api/meta` 的 `public_key` 字段下发。
- **小站验签**：只拿公钥，纯本地算，不需要私网/联网。主站公钥验不过时再拿本机公钥试一次
  （小站自己的管理员登录走这条）。
- **身份映射**：token 里的 `uid` 是权威 id。小站按 `users.master_uid` 找影子行，
  找不到就建一条（`u<uid>`），**绝不退回本地 id** —— 否则主站 uid=2 会认成本站 id=2 的另一个人。
- **黑名单**：`blacklist(uid, ts, reason, banned, synced_at)`。
  `banned=0` 是解封墓碑，不能删行，否则小站永远收不到「解封」这条增量。
  条目列表规范化 JSON 后用主站私钥签名，小站验不过就一条都不收。
- **拦截点**：`optional_user` / `require_user`（读接口也过这两条），403 + 固定文案「账号已被封禁」。
- **配置**：`site.site_id`、`site.master_url`（空=主站）、`auth.public_key`、
  `auth.blacklist_pull_seconds`（默认 60）。
- **自检脚本**：`server/tool/`（`check_stage2.py` 纯离线、`check_e2e.py` 单站端到端、
  `check_slave.py` 主从同步、`check_unban.py` 解封传播、`check_offline.py` 断网验签）。

### 第 3 段落地细节

- **`api` 版本**：`sites.API_VERSION = 2`。1 = 只有帖子和用户，2 = 站点自述 / 清单 / 登记。
  `/meta` 的 `capabilities` 现在有 `jwt-eddsa`、`blacklist`、`meta`、`manifest`、`sites`、`register`。
- **自述形状**：`/meta` 和 `/.well-known/bbs.json` 的 `sites[i]` 是同一套字段：
  `id / name / description / url / endpoints / api / lang / icon / tags / open / contact / updated`。
  `/meta` 额外带 `site_id`、`base_url`（老名字，兼容）、`capabilities`、`public_key`、`blacklist`。
- **配置**：`site.lang / icon / tags / contact / endpoints / open`，`sites.allow_private`、
  `sites.register_per_hour_ip`。`endpoints` 空就只报 `base_url`。
- **登记**：`POST /api/sites/register`，只 `url` 必填。主站回访对方 `/meta`（先 `/api/meta` 再 `/meta`），
  按站名 slug 分配 id，中文名转不出 slug 就用 `site-<hash4>`；幂等、查重、内网默认拒绝。
- **小站自动登记**：配了 `master_url` + `base_url` 且 `site_id` 为空，后台线程去登记，
  拿到的 id 存 `sync_state.assigned_site_id`，`/meta` 立刻报出来。失败退避 5s→10s→…→5min。
- **目录**：`GET /api/sites`，格式同 `bbs.json`，客户端可直接导入；`DELETE /api/sites/{id}` 管理员摘站。
- **校验**：`server/app/sites.py: validate()` 与 `lib/site_meta.dart: parseManifest()` 同一套三条规则，
  `server/tool/check_stage3.py`（离线）和 `test/site_meta_test.dart`（客户端）各跑一遍。
- **客户端**：启动读一次自述，`api` 高于 `SiteMeta.supportedApi`（当前 2）就在首页顶部顶一条
  「请更新客户端」，只提示不拦用。`Api.loadMeta()` 先 `.well-known` 后 `/api/meta`，两次都失败静默。

### 第 4 段落地细节

- **站点表**：`lib/sites.dart` 的 `SiteEntry`（id / name / urls / api / icon / lang / master），
  运行时另有 `reachable`、`lastOk`，不落盘。存 SharedPreferences `sites_v1`（`lib/site_store.dart`），
  解析失败当空表，不抛。
- **升级不丢地址**：老版本只存 `server_base`。首次启动读到空表时，把它 + 出厂 `SiteConfig.servers`
  +（网页版）当前 origin 合成一座站写回，用户填过的地址不会丢。
- **选路**：`Api.endpoints` 是一行站的入口列表，`Api.probe()` 逐条真发 `/api/feed`，
  v6 入口 3 秒、其余 10 秒，串行，全通时稳定落在前面那条；`Api._withFailover` 在请求失败时按同一顺序换入口，
  服务器回了 `ApiException` 就不换（那不是路的问题）。切网络回前台会重探一次（5 秒节流）。
- **v6 判定**：只认三种写法——IPv6 字面量（含 `:`）、`ipv6` 开头域名、带 `-v6.` 的域名。别的域名不猜。
- **合并去重**：`mergeSites()` 先按 `id` 认，其次按地址重叠认，都对不上才追加；登录站强制唯一，
  一座都没有时第一座顶上。
- **站点管理页**（`lib/pages/sites_page.dart`，原 `server_page.dart` 已删）：一行一座站，
  左侧圆点标连通（灰=连不上、主色=通、空心=没探过），连不上的行变灰且点不动，
  标「登录站」「当前」。操作：加站、切换、设登录站、删除（确认）、粘贴清单、
  从主站拉 `GET /api/sites` 一键导入。导入结果按 `no_url / duplicate_id / api_too_new / bad_format`
  分类报「跳过几条、为什么」。
- **登录站**：注册、登录、找回密码走 `Api.postAt(loginUrls, …)`，只发登录站，站内按入口顺序回落；
  token 全局共用，换站只重新拉一次 `/me`，不用重登。
- **封禁页**：`_decode` 见 403 且 detail 含「账号已被封禁」就置 `AppState.banned`，
  `main.dart` 的 `_Root` 把整棵树换成 `banned_page.dart`，只留「退出登录」（退出清标记）。
- **空表引导**：`_Root` 在 `ready && sites.isEmpty` 时出 `setup_page.dart`，
  手填地址连不上也入表（标灰）并在原地报错，不用再去设置里找。

### 第 5 段落地细节

- **配置**：新增 `server`（`host` / `port` / `tls_cert_dir`）和 `backup`（`dir` / `keep`），
  `update.check_url` 给自检脚本用。端口从命令行搬进 `site.json`，`run.sh` 和容器入口都读它；
  环境变量仍优先。没配好时行为跟以前一样（8080、明文）。
- **`_cfg.sh`**：`run.sh` / `backup.sh` / `restore.sh` / `check_update.sh` 共用的读配置函数，
  只依赖 python3 的 `json` —— 裸机上还没装依赖时也读得动，读不到就静默退回默认值。
- **`install.sh`**：检 python ≥ 3.9 / venv / tar → 写 `config/site.json`（从 example 去掉 `_说明` 键；
  已有配置只补缺的键，先备份成 `site.json.bak.<时间>`）→ 建 venv 装依赖 → `db.init()` →
  `ensure_admin()` 打印管理码。`--docker` 跳过 venv 和建库，交给容器首次启动。
- **容器**：`python:3.12-slim`，只拷服务端（`app/` `static/` `templates/`），`data` `config` `logs` 三个卷；
  默认 `network_mode: host`，容器内监听端口由 `site.json` 决定，改端口不用改 compose，重启即可。
  `.dockerignore` 挡掉真数据、真配置、`.venv` 和 `web/`。入口脚本每起一次跑 `db.init()`，升级时自动补列。
- **备份**：文件名精确到秒（同一分钟跑两次不会互相覆盖），先 `.backup` 再 `--check`，验不过不写文件；
  目录和保留份数读 `site.json`，老的 `OPENBBS_KEEP` 还认。
- **恢复**：`restore.sh` 解包 → 验快照（users / threads / replies 查得动）→ 现有数据打包留底 →
  停站 → 换库（顺手删 `-wal` / `-shm`）→ 起站。任何一步失败都在覆盖前退出。`--db-only` 只还库不动图片。
- **升级**：`check_update.sh` 拉一个 JSON 比版本号，只打印「当前 X，最新 Y」和说明，
  不下载、不替换；有新版本退出码 1，方便挂 cron 接通知。
- **实测**（`/tmp` 下复制目录跑，不碰线上）：
  - 容器形态：`install.sh --docker` 写出的 `site.json` 端口 8099，改 9100 后 `run.sh` 起在同一端口，`/api/meta` 200。
  - venv 形态：`install.sh` 装依赖、建库、生成管理码，9200 起站 200。
  - 备份恢复：插入探针用户 → `backup.sh` → 删掉 → `restore.sh` → 探针回来，站能起，`/api/meta` 200。
  - 本机 docker 没有 socket 权限，镜像构建没实测；`docker compose config` 解析通过。
- **自检**：`server/tool/check_stage5.py`，纯离线，查配置段、脚本语法、镜像要拷的文件、备份恢复链路。

### 第 2 段未做

- `E1` 的「展示时按主站地址取资料」只做了影子行占位（`u<uid>`），
  昵称/头像仍是小站自己的，没走主站资料接口。等第 3 段 `/meta` 稳定后补。

### 第 6 段 · 搜索与内容安全

- **索引**：`threads_fts` / `replies_fts` 两张 FTS5 表，`tokenize='trigram'`，中文能按子串搜（3 字起）。
  没用 external content：trigram 配 external content 时 FTS5 的 `'delete'` 命令在本机实测会报
  `database disk image is malformed`，宁可正文在索引里多存一份。
- **同步**：`db.fts_upsert_thread` / `fts_upsert_reply` / `fts_delete` 三个函数，
  挂在建帖、改帖、删帖、回帖、改回复、删回复六处，都在 `commit()` 之前调。
  漏一处就是「改了搜不到」，验收里专门查这条。
  老库第一次启动靠 `init()` 比对两边行数，对不上就整表重灌一份。
- **接口**：`GET /api/search` 路径没变，加 `kind`（thread / reply / user / all）和 `sort`。
  ≥3 字走 `MATCH '"用户输入"'`（引号包成短语，`OR` `*` `(` 当不了操作符），1–2 字回退 `LIKE`；
  搜人始终走 `LIKE`（name / nickname / handle 三列）。空 `q` 不查库，直接回空三段。
  返回 `items` / `replies` / `users` / `page` / `total` / `kind` / `took_ms`，键一个不少，老客户端照旧能用。
- **敏感词**：`server/config/sensitive.txt` 一行一个词，`app/words.py` 每次 check 前 stat 一下 mtime，
  变了就重编正则，改完不用重启（IPv4 / IPv6 两个实例各看各的）。
  命中回 400 且文案里带那个词；管理员放行，方便站长发公告。
  拦截点：发帖、改帖、回帖、改回复、改昵称与签名、注册用户名、私信正文。
- **图片黑名单**：`server/data/image_block.txt` 一行一个 sha256，`upload` 算完哈希、落盘之前拦。
  管理接口 `POST /admin/image/block|unblock`、`GET /admin/image/blocked` 收的是 `/img/` 地址 ——
  文件名只有哈希前 20 位，反推不出来，接口按地址读文件现算。
- **人机校验**：`GET /api/register/challenge` 发一道加法题，`challenge_id` 形如 `<token8>.<exp>`，
  签名是 HMAC 前 32 位十六进制，不落库、不存表。`auth.register_challenge` 默认关着
  （老客户端发版前不打开），打开后缺字段 / 过期 / 签名对不上 / 答案错各有各的报错。
- **验收**：
  - 服务端 39 项接口验收全过（临时库 `/tmp/t1.db`）：建帖→搜得到、改标题→新标题搜得到旧标题搜不到、
    删帖删回复→搜不到、1 / 2 / 3 字查询都不 500、敏感词 400 且带词、管理员发同样内容 200、
    帖子和私信都被拦。
  - 客户端 `flutter analyze` 0 error（55 条 info 是老问题）、`flutter test` 68 项全绿，含 l10n 对齐。
  - 备份镜像：主备份与镜像两份 sha256 成对相同；未配镜像退出 0；镜像目录不可写退出 2 且主备份还在；
    `restore.sh --from-mirror` 能挑出最新一份并通过快照自检。
- **验收中补的两处漏**：`PATCH /api/me` 的昵称、签名原来没过词表；私信图片原来是把不合法的路径
  静默丢掉，现在按约定报 400。
- **已知边界**：trigram 只支持 ≥3 字，2 字靠 `LIKE` 全表扫；词表是「包含」匹配，短词会误伤
  （比如收了「色情」，正常的「颜色情况」也中）；索引里多存一份正文，库会大一圈；
  管理员不过词表，站长自己也得注意。

### 第 7 段 · 私信与异地备份

- **数据**：`dm_threads(a_id, b_id, last_id)` 两列 id 恒按 `a_id < b_id` 存，靠唯一键保证两个人只有一条会话；
  `dm_messages(thread_id, from_id, to_id, body, images, is_read, created_at)`。
  索引 `(thread_id, id DESC)`、`(to_id, is_read)`、`dm_threads(last_id DESC)`。
  `id` 是站内自增，不跨站，也不做跨站私信。
- **接口**（全部 `require_user`，读接口也一样 —— 私信不是公开内容）：
  `GET /dm` 会话列表（按 last_id 倒序，只列有消息的）、`GET /dm/{uid}` 取会话（首次给最新 30 条，
  正序，顺手把别人发给我且未读的标已读）、`POST /dm/{uid}` 发、`POST /dm/{uid}/read` 显式已读、
  `GET /dm/unread` 角标用。
  发送校验：不能发给自己 400、对方不存在 404、空 400、正文 2000 字以内、图最多 9 张且必须 `/img/` 开头、
  过敏感词。会话不存在就按 min/max 建。
- **通知**：发一条 `kind='dm'`，`body` 留空 —— 通知表能被别的入口读到，正文不许进。
- **客户端**：`inbox_page.dart` 会话列表、`chat_page.dart` 对话页（气泡、图片走 `PostImages`、上滑加载更早）；
  入口三处：抽屉「私信」、别人主页「发私信」、消息页顶部「私信 · N 条未读」。
  未读合并进底部「消息」角标（通知未读 + 私信未读，不加第二个角标）。
  刷新靠 15 秒轮询，页面不可见就停；不做长连接、不做推送。
- **备份**：`site.json` 的 `backup` 段多了 `mirror_dir` / `mirror_keep`，
  目录和份数全从配置读（`BACKUP_OFF` 仍可覆盖，方便试跑）。
  流程变成：写主备份 → 清主目录旧份 → 镜像（`mkdir -p`、`cp -a`、比对 sha256）→ 清镜像旧份。
  镜像这轮没成只影响退出码（`2`），本地那份不动；两份在同一块盘时日志提醒一句。
  文件名精确到秒，同一分钟跑两次不再互相覆盖。
- **恢复**：`restore.sh --from-mirror` 从 `mirror_dir` 挑最新一份，找不到就把目录里实际的文件列出来；
  「先给现有数据留底」那一步不变。
- **验收中补的漏**：本机 `run.sh` 原来没有 `--stop`，`restore.sh` 的停站那步是空转 ——
  库换掉了，老进程还攥着旧文件，页面看到的还是旧数据。已补 `--stop`（读 `data/forum*.pid` 逐个 kill），
  并在 11-04 21:14 真跑一遍 `restore.sh --from-mirror --yes`：四个进程全停、覆盖、起站，
  恢复后用户 14 / 帖 18 / 回复 8 与恢复前一致，`/api/meta` 正常、图片 200。
- **验收**：
  - 服务端：建库跑两次 `init()` 不报错；两人互发、列表、分页、已读、未读数全对；
    发自己 400、空 400、超长 400、对方不存在 404；被封账号调 `/dm` 得 403「账号已被封禁」；
    私信命中敏感词 400；通知表里 `kind='dm'` 的 `body` 全为空。
  - 客户端：`analyze` 0 error、`test` 全绿；抽屉、主页、消息页三个入口都在。
  - 备份：`bash -n` 两个脚本；临时镜像目录跑一遍两份哈希相同；镜像不可写退出 2 主备份仍在；
    未配镜像退出 0；真跑一次写到 `/vol2/openbbs_backup`，与本地那份 sha256 一致。
- **已知边界**：只做一对一、不做群聊 / 撤回 / 已读回执给对方看 / 附件 / 跨站；
  15 秒轮询有延迟，通知栏推送另算一项。
