# OpenBBS 全项目分段 Debug 提示词（五段）

写于 2026-11-05。用途：把整个项目切成五段，一段一份提示词，逐段跑一遍系统排查。
每段都能单独复制出来直接用，不依赖上一段的结果；但**顺序建议照 1→2→3→4→5 走**，第 5 段是收口回归。

盘面事实（写提示词时核对过，2026-11-05）：

- 线上服务端：`/vol1/1000/data/code/ongoing/bbs/server`（**权威**，78 个路由，5685 行）
- 客户端：`/vol1/1000/data/code/ongoing/openbbs`（98 个 dart 文件，30218 行）
- `openbbs/server` 是落后副本，缺 11 个路由，**排查一律以 bbs/server 为准**
- 数据库 `bbs/server/data/forum.db`（WAL），上传 `data/uploads`，云盘 `/vol3/1000/cloud/files`
- 4 个 uvicorn：8080 明文（v4+v6）、26016 TLS（v4+v6），cron `*/2` 保活
- 客户端 1.4.2+108，stable/beta 同包

---

# 第 1 段：接口与数据层

## 角色

你是这个论坛的后端排查者。目标不是重写，是**找出真实存在的错误**：数据不一致、权限漏洞、边界崩溃、错误码误用。没有证据的怀疑一律不写。

## 范围

- 代码：`bbs/server/app/api.py`（3042 行，78 路由）、`db.py`（迁移与建表）、`auth.py`（token）、`main.py`（路由挂载）
- 数据：`forum.db` 全部业务表，重点 `users / threads / replies / likes / notifications / favorites / history / follows / reports`
- 不碰：文件存储细节（第 2 段）、私信（第 3 段）、前端（第 4 段）、部署（第 5 段）

## 前置动作（必须做）

```bash
cd /vol1/1000/data/code/ongoing/bbs/server
python3 db_snapshot.py data/forum.db data/backups/debug1_$(date +%Y%m%d_%H%M%S).db
python3 db_snapshot.py --check data/backups/debug1_*.db | tail -3
```

只有确认 `forum.db` 至少一份可打开的快照在手，才允许开始。排查期间**只读**，除非发现明确缺陷并经确认。

## 检查项（逐条给结论，不许跳过）

1. **鉴权边界**
   - 未带 token 访问每个需要登录的路由，是否 401 而不是 500 或 200 空数据
   - 拿 A 的 token 去改 B 的帖 / 删 B 的回复 / 读 B 的收藏，是否 403
   - `/admin/*` 全部：普通用户访问是否 403；`is_admin=0` 的 level=99 用户是否被误放行
   - shadow 用户（小站同步来的人，`master_uid` 非空）能否越权读本机用户数据

2. **输入校验**
   - 长度：标题 120、正文 20000、楼层 2000、昵称与用户名上下限，超长是截断还是 400（两者选一并确认所有入口一致）
   - 图片只收 `/img/` 开头且不含 `..`；附件 `files` 是否逐个校验属主（别人的 digest 能不能挂到自己帖子上）
   - `reply_id` 是否校验同一帖；私信侧是否校验同一会话
   - 不存在的外键（给已删帖子回复、给已删用户发私信）返回什么

3. **分页与排序**
   - `per_page` 默认 20，超大值传 `?per_page=10000` 是否被限制
   - 翻页时新帖插入会不会导致重复/漏条
   - 同一秒创建的记录排序是否稳定（必须有 id 兜底）
   - 楼层号 `floor_no` 在删除回复后是否出现空洞，客户端怎么显示

4. **计数一致性（写 SQL 对账）**
   - `threads.reply_count` 与实际 `replies` 行数
   - `threads.agree_count` / `replies.agree_count` 与 `likes` 行数
   - `view_count` 是否只增不减、是否被刷新页面刷
   - 任何一条对不上，记录差异样本（帖 id、字段、两个值）

5. **事务安全**
   - 发帖 → 写文件账本 → 写通知，中途异常是否留半截数据
   - 点赞是否幂等（连点两次会不会双计数 / 报错）
   - 删帖时级联：回复、点赞、收藏、通知、文件账本各自是否清理，清理是否在一个事务里

6. **通知**
   - 自己给自己点赞、自己回复自己、自己 @ 自己，是否产生通知
   - 同一个人连续点赞又取消，通知是否堆积
   - 已删帖子的通知点进去会怎样

7. **全文搜索（FTS5）**
   - 发帖 / 改帖 / 删帖后 `threads_fts` 是否同步（用 `SELECT rowid FROM threads_fts WHERE threads_fts MATCH ...` 验证）
   - 回复的 FTS 是否同步
   - 中文分词表现：搜两个汉字能不能命中（FTS5 默认分词对中文按字切，确认实际行为）
   - 关键：**改帖后旧内容还能不能搜到**（这是最容易烂的地方）

8. **等级与权限联动**
   - `_level_of` 的公式与实际等级是否一致
   - 降级场景（删帖后等级是否回落，若刻意不回落写明）
   - `max_level=99` 时管理员是否被普通逻辑覆盖

9. **错误语义**
   - 400 / 403 / 404 / 409 / 429 是否各自承担明确含义
   - 前端能不能区分「没登录」和「被封禁」（`bannedMessage` 依赖这个）
   - 有没有把内部异常原文直接抛给用户（泄露路径、SQL）

10. **并发与时间**
    - `time.time()` 秒级精度下，同一秒的插入顺序
    - 两个请求同时给同一帖子点赞
    - 注册并发同名用户（`name` 是否唯一索引）

## 验证手段

```bash
# 只读冒烟（303 = 本地明文口）
S=http://[::1]:8080/api
curl -s $S/feed | head -c 300
curl -s -o /dev/null -w "%{http_code}\n" $S/me          # 期望 401
curl -s -o /dev/null -w "%{http_code}\n" $S/admin/users # 期望 401

# 计数对账
python3 - <<'EOF'
import sqlite3
c=sqlite3.connect('/vol1/1000/data/code/ongoing/bbs/server/data/forum.db')
bad=c.execute("""SELECT t.id,t.reply_count,(SELECT COUNT(*) FROM replies r WHERE r.thread_id=t.id)
                 FROM threads t WHERE t.reply_count<>(SELECT COUNT(*) FROM replies r WHERE r.thread_id=t.id)""").fetchall()
print("reply_count 不一致:", bad)
EOF
```

## 输出格式

1. **结论**：一句话，几处 P0、几处 P1
2. **问题清单**：每条含 `级别 | 位置 file:line | 现象 | 复现步骤 | 期望 vs 实际 | 影响面`
3. **证据**：命令 + 输出摘录，不超过 20 行/条
4. **修复建议**：最小改动，给出具体代码位置和改法，不写大重构
5. **未覆盖项**：说明哪些没查、为什么

## 硬约束

- 不改 `config/site.json`，不重启进程，不动数据（除快照）
- 不猜。每条结论必须有命令输出或 SQL 结果支撑
- 不做与本段无关的重构，不顺手改 UI 文案
- 发现问题先记录，**不擅自修**；等确认

---

# 第 2 段：文件与存储链路

## 角色

你是文件链路的排查者。这条链最长：客户端选文件 → 上传 → digest 落盘 → 账本记账 → 帖子/云盘引用 → 下载 → 回收站 → 物理删除。任何一环漏了，表现都是「文件不见了」或「空间不对」。

## 范围

- 服务端：`files.py`、`api.py` 的 `/upload` `/file` `/cloud/*` `/t/{tid}/replace-images`、`thumbs.py`
- 数据：`user_files`（账本）、`files`（全局 digest 表）、`threads.files/images`、`replies.files/images`、`dm_messages.files`
- 磁盘：`bbs/server/data/uploads`（18MB）、`/vol3/1000/cloud/files`（14MB）
- 客户端：`lib/file_browser*.dart`、`lib/downloads*.dart`、`lib/file_open*.dart`、`lib/cloud.dart`、`pages/cloud_page.dart`、`pages/cloud_pick_page.dart`

## 前置动作

```bash
cd /vol1/1000/data/code/ongoing/bbs/server
python3 db_snapshot.py data/forum.db data/backups/debug2_$(date +%Y%m%d_%H%M%S).db
du -sh data/uploads /vol3/1000/cloud/files
find data/uploads -type f | wc -l
```

记下三个基准数：账本行数、物理文件数、字节总数。后面全靠这三个数对账。

## 检查项

1. **账本 vs 磁盘对账**
   - `user_files` 里 `deleted_at IS NULL` 的 digest 集合，与磁盘文件集合的差集（两边都列）
   - 孤儿文件（磁盘有、账本无）；幽灵文件（账本有、磁盘无）
   - 幽灵文件会让下载 500，必须逐个列出

2. **引用计数与删除安全**
   - 一个 digest 被几个帖子/回复/私信引用（扫 `threads.files`、`replies.files`、`dm_messages.files`）
   - 删云盘文件时，引用 > 0 的是否拒绝或提示；已经是「删了但帖子还在引用」的，帖子那边显示什么
   - 物理删除条件：账本无引用 + 回收站过期，是否两个条件都验

3. **回收站与配额**
   - 删除 → `deleted_at` 置位、仍占额度
   - 每小时清理：超 7 天的真删；超配额时「先删最旧」的顺序是否符合预期（按 deleted_at 还是 created_at）
   - 彻底删除（`DELETE /cloud/trash/{fid}`）后额度是否立刻回落
   - 额度计算方式（SUM 未删 + 回收站）与后台显示是否一致
   - 每人 5G 默认、`quota_bytes` 覆盖逻辑、0 或空表示回落到全站默认

4. **上传路径**
   - `/upload` 图片：5MB / 动图 10MB / 最多 9 张，超限报什么
   - `/file` 附件：单文件上限、每日个数与字节额度是否真的关掉了（`site.json` 里 0 = 关），关了以后有没有残留的 413
   - 请求体上限（uvicorn 默认无限制，但反向代理或中间件可能有）
   - 同名不同内容 / 同名同内容 / 不同用户同文件，digest 是否共用一份
   - 并发上传同一文件是否互相踩

5. **缩略图**
   - `thumbs.py` 生成规则、缓存位置、原图删了缩略图是否成孤儿
   - 网页端取缩略图、App 取原图的判断在哪，判断错了会白图

6. **帖子附件与云盘的联动**
   - 发帖带附件 → `source='post'`、`public=1`、`thread_id` 记上
   - 删帖 → 退回私人（`public=0`）、空间不退
   - 编辑帖子删附件 → 账本怎么变
   - 云盘删了被帖子引用的文件 → 帖子详情页是否显示失效卡片而不是崩溃

7. **下载链路**
   - `/api/file` 鉴权：帖子附件公开、私人文件仅本人、未登录能不能下帖子附件
   - 断点/大文件：500MB 下载是否流式（不能整块进内存）
   - 中文文件名、特殊字符、Content-Disposition 编码
   - 客户端下载落盘位置（`Download/OpenBBS`）、重名处理、「已下载」标记的判据（大小？digest？）

8. **客户端选文件与打开**
   - 安卓文件浏览器需要「所有文件访问权限」，没权限时的引导路径
   - Android 11+ 看不到 `Android/data`、`Android/obb` 是否给出说明（不是静默空目录）
   - 选中多文件、取消选择、返回键各走哪条路
   - Web 端：`file_browser_web` 退回 `<input type=file>`，多选是否可用

## 验证手段

```bash
# 对账脚本（只读）
python3 - <<'EOF'
import sqlite3, os, hashlib
DB='/vol1/1000/data/code/ongoing/bbs/server/data/forum.db'
c=sqlite3.connect(DB)
ledger={r[0] for r in c.execute("SELECT digest FROM user_files WHERE deleted_at IS NULL")}
print("账本条目:", len(ledger))
for root in ('/vol1/1000/data/code/ongoing/bbs/server/data/uploads','/vol3/1000/cloud/files'):
    disk=set()
    for dp,_,fs in os.walk(root):
        for f in fs: disk.add(f.split('.')[0])
    print(root, "磁盘:", len(disk), "幽灵:", len(ledger-disk), "孤儿:", len(disk-ledger))
EOF
```

## 输出格式

同第 1 段：结论 / 问题清单（含级别与位置）/ 证据 / 最小修复建议 / 未覆盖项。
额外要求：**给一张对账表**——账本条数、磁盘文件数、幽灵数、孤儿数、字节合计，四项两两能对上。

## 硬约束

- 只读对账，**不删任何文件**，不做清理
- 不重跑清理任务（会真删）
- 客户端部分只做静态审阅 + 现有包行为验证，不改代码
- 发现额度或回收站逻辑缺陷，先算清影响面（涉及多少用户多少字节）再报

---

# 第 3 段：消息系统（私信 + 站内消息）

## 角色

你是消息系统的排查者。这块最容易被「看起来对」骗过去：未读数、置顶、隐藏、互关限制、红点，五个状态互相覆盖，错一处就全歪。

## 范围

- 服务端：`api.py` 的 `/dm/*`（`/dm`、`/dm/{uid}`、`/dm/{tid}/state`、`/dm/{uid}/read`、`/dm/unread`）、`/notifications*`
- 数据：`dm_threads`、`dm_messages`、`dm_state`、`notifications`
- 客户端：`pages/messages_page.dart`、`pages/chat_page.dart`、`pages/notice_page.dart`、`home_page.dart` 的红点逻辑

## 检查项

1. **会话唯一性**
   - `_pair(a,b)` 保证同两个人只有一条线程；反序（A→B、B→A）是否落到同一行
   - 自己给自己发私信
   - 对方账号被删/被封后，会话是否还列得出来
   - 同一对用户并发首次发信是否产生两条线程

2. **互关限制**
   - 未互关单向只能发一条（`_dm_quota_left`）：数的是「我发给他的条数」还是「整个会话」；对方回一条后是否解锁
   - 关注 → 取关 → 再发，额度怎么算
   - 被限制时错误信息是否明确（403 + 人话）

3. **未读与已读**
   - `is_read` 单一标记能否支撑「多端已读」
   - `/dm/unread` 的计数与列表页红点是否同一口径（私信 + 站内消息相加）
   - 进入会话何时置已读：打开页面、滚到底、发消息各是什么行为
   - 已读后红点是否立刻消失，还是等下一次轮询

4. **会话状态三件套**
   - 置顶（`pinned`）、免打扰（`muted`）、隐藏到某条（`hidden_upto`）是否能同时生效
   - 删除会话（隐藏）后对方再发，是否重新出现在列表
   - `dm_state` 与 `dm_threads` 的写入是否可能互相覆盖（读改写竞争）

5. **消息内容**
   - 引用（`reply_id`）必须同会话，跨会话 id 是否被忽略
   - 附件（`files`）是否校验属主与存在性
   - 图片只收 `/img/`
   - 正文 2000 字上限、空消息（只有附件）是否允许
   - 被屏蔽词拦截时，会话里是否会留半条

6. **站内消息合并**
   - 私信是否会重复进 `notifications`（要求：不进）
   - 站内消息长按删除只清列表，记录保留
   - 两类混排的排序键是否统一（都是 created_at）

7. **轮询与红点**
   - 15 秒轮询在有网/无网/切后台的三种表现
   - 轮询失败是否会无限重试打爆服务端
   - 红点数（数字）与列表未读是否一致；超过 99 怎么显示
   - 多站同时有未读时，红点聚合口径

## 验证手段

```bash
python3 - <<'EOF'
import sqlite3
c=sqlite3.connect('/vol1/1000/data/code/ongoing/bbs/server/data/forum.db')
print("线程:", c.execute("SELECT COUNT(*) FROM dm_threads").fetchone()[0])
print("重复对:", c.execute("""SELECT a_id,b_id,COUNT(*) n FROM dm_threads
    GROUP BY a_id,b_id HAVING n>1""").fetchall())
print("自聊:", c.execute("SELECT id FROM dm_threads WHERE a_id=b_id").fetchall())
print("未读:", c.execute("SELECT COUNT(*) FROM dm_messages WHERE is_read=0").fetchone()[0])
print("孤儿消息:", c.execute("""SELECT COUNT(*) FROM dm_messages m
    WHERE NOT EXISTS(SELECT 1 FROM dm_threads t WHERE t.id=m.thread_id)""").fetchone()[0])
EOF
```

## 输出格式

同前。额外：**画一张状态机**（未读/已读、置顶、隐藏、免打扰各自的触发与清除条件），标出任何「状态互相打架」的路径。

## 硬约束

- 不删消息、不清未读、不改 `dm_state`
- 需要造数据验证时，用临时快照库 `debug3_*.db`，**不在线上库造**
- 客户端只审阅现有实现，不改交互

---

# 第 4 段：客户端界面与本地状态

## 角色

你是客户端排查者。这一段的敌人不是崩溃，是「偶尔不对」：缓存陈旧、入口连不上、草稿丢了、更新提示不来、切后台回来白屏。

## 范围

- 全部 `openbbs/lib`，重点：`api.dart`（失败回落）、`sites.dart` + `site_config.dart`（多入口）、`store.dart` / `token_store.dart`（本地存储）、`disk_cache*` / `img_cache*`（缓存）、`draft_images*`（草稿）、`update*.dart`（更新提示与强更）
- 34 个页面里的流程：登录、发帖、编辑、私聊、云盘、设置、站点管理
- 平台分叉：所有 `*_io.dart` / `*_web.dart` 成对文件

## 检查项

1. **入口发现与回落**
   - 内置两个入口（v6 直连、v4 中转）+ 局域网，探活超时 6 秒
   - 一个入口不可用时，请求是否重试到另一个；失败后多久再探
   - 站点自述（`/.well-known/bbs.json`）合并逻辑：服务端少写端口会不会把地址冲掉（历史坑）
   - 手动添加站点、删除站点、切换站点后，缓存与 token 是否跟着切

2. **登录与 token**
   - token 过期/被封时，全局是否统一跳登录（不能每个页面各弹一次）
   - `bannedMessage` 的触发条件
   - token 存哪（`flutter_secure_storage`），Web 端存哪（localStorage？），退出登录是否清干净
   - 多账号切换（`accounts.dart`）残留问题

3. **缓存**
   - 磁盘缓存目录大小、清理入口（设置页「清除缓存」）
   - 缓存失效判据（时间？版本号？）
   - Web 端缓存（IndexedDB/内存）与刷新不生效的关系
   - 图片缓存开了 `memCacheWidth`（Web 端靠 platform interface），大图会不会顶爆

4. **草稿**
   - 发帖页退到后台/被系统杀，草稿图能否恢复
   - 草稿与账号绑定，换账号会不会串

5. **更新提示与强更**
   - `check_hours=0` 时回前台就查；`force_below` 之下强制
   - 管理员拿 beta、普通人拿 stable（服务端分流），客户端有没有硬编码通道
   - 降级安装（build 变小）的提示文案
   - 下载 APK 到安装的整条链路权限是否齐

6. **权限**
   - 「所有文件访问」在 Android 11/13/14 的差异表现
   - 相册权限（`photo_manager`）被拒后的降级路径
   - 通知权限没开时，更新提示是否静默失效

7. **跨端一致**
   - 同一功能在 Web 与 App 的差异清单（发文件只能系统选择器、下载落盘、打开文件）
   - 差异是否在界面上有说明，而不是让用户以为坏了

8. **界面稳定性**
   - 深色主题、大字号、窄屏下是否有溢出
   - 长列表滚动位置（`scrollable_positioned_list`）跳楼
   - 输入框在键盘弹起时的遮挡

## 验证手段

```bash
cd /vol1/1000/data/code/ongoing/openbbs
bash -lc 'source /vol1/1000/data/code/.fenv && flutter analyze lib/'
bash -lc 'source /vol1/1000/data/code/.fenv && flutter test'
bash -lc 'source /vol1/1000/data/code/.fenv && flutter build web --release --base-href / --no-web-resources-cdn --pwa-strategy=none'
```

真机项（必须列清楚哪些只能真机验）：更新提示、覆盖安装、切后台轮询、安全存储、文件权限弹窗。

## 输出格式

同前。额外：**一张「代码里认定可行 / 只有真机能定」的清单**，别把没法验的写成已验。

## 硬约束

- 不改交互与视觉，只记录问题
- 不动 `lib/api.dart` 的通道常量（改了会让老包连不上）
- 需要重新构建只用于验证时，产物不进通道，别覆盖 stable

---

# 第 5 段：部署、发布与收口回归

## 角色

你是这一轮排查的收口人。前四段修了什么，这一段证明「线上是真的好的」，并且把发布链路验一遍——**发布链路本身也是被测对象**。

## 范围

- 进程：`run.sh`（4 个 uvicorn）、cron `*/2` 保活、`data/forum*.pid`
- 入口与证书：8080 明文、26016 TLS、`~/certs/main`、续期钩子、`/go` 兜底页
- 中间层：CORS 白名单、`Host=share` 的 301（历史遗留）
- 静态：`server/web`、`/img`、`/apk`、`/static`、自毁 SW、canvaskit 本地化
- 备份：`backup.sh`（本地 30 份 + `/vol2/openbbs_backup` 镜像 14 份）、`restore.sh`、`db_snapshot.py`
- 发布：`release.sh`（包名校验）、`deploy_web.sh`、`data/apk/{stable,beta}/notes.txt`
- 网络：DDNS（`cf_ddns.py`）、樱花 frp（24016）

## 检查项

1. **进程与自愈**
   - 4 个进程都在、监听 v4+v6；杀掉一个，2 分钟内 cron 是否拉起
   - 重启后 `/api/feed` 两个端口都通；pid 文件不残留脏 pid
   - 日志 `logs/forum.log` 有无持续报错、有无 5xx 堆积

2. **入口与证书**
   - `ipv6bbs:26016` 直连、`ipv4bbs:24016` frp 兜底，两条都通
   - 证书剩余天数、续期钩子是否可执行
   - CORS：从两个入口打开的网页都能调接口（换入口后「接口全挂」是历史故障）

3. **静态资源**
   - `flutter_service_worker.js` 是自毁版（不能把站点钉在旧缓存里）
   - `flutter_bootstrap.js` 末尾有 `"useLocalCanvasKit":true`
   - `index.html` 的 base href 是 `/`
   - `/go` 兜底页没被部署覆盖
   - 预压缩文件与源文件一致，`main.dart.js` 可正常下载

4. **备份与恢复**
   - 最近一次备份时间、大小、日志无错
   - 镜像目录有第二份
   - **做一次恢复演练**：把某份备份恢复到临时库，`db_snapshot.py --check` 通过，抽查 users/threads 行数
   - 保留份数是否真的按配置裁（30 / 14）

5. **发布链路**
   - `release.sh` 包名校验生效（故意用手错包试一次会拒）
   - `pubspec.yaml` 版本、APK 实际 versionCode/versionName、`notes.txt` 段头三者一致
   - `/api/app/latest` 对未登录、普通用户、管理员三种身份返回正确通道
   - 同版本号重复发布会覆盖同名文件（要确认这不是意外）
   - beta 空目录回退 stable 的逻辑

6. **网络层**
   - DDNS 记录与当前 IPv6 一致（`ipv6bbs` 等）
   - frp 隧道在线（24016 → 本机 26016）
   - 8080 只该在局域网用；外部扫描是否只打到 301 或 404

7. **收口回归（前四段的结果在这里验）**
   - 核心流程走一遍：注册/登录 → 发帖（带图带附件）→ 回复 → 点赞 → 收藏 → 私信（含附件）→ 云盘上传下载 → 删除
   - 每个动作在两个端口各验一次
   - 客户端：装 1.4.2+108，五项真机检查过一遍

## 验证手段

```bash
bash /home/060923/AstrBot/data/skills/timeline-forum/scripts/status.sh

# 两个入口
curl -s -o /dev/null -w "8080 %{http_code}\n" http://[::1]:8080/api/feed
curl -sk -o /dev/null -w "26016 %{http_code}\n" https://127.0.0.1:26016/api/feed

# 证书
openssl x509 -enddate -noout -in /home/060923/certs/main/fullchain.pem

# 备份
tail -20 /vol1/1000/data/code/ongoing/bbs/server/logs/backup.log
ls -lt /vol1/1000/data/code/ongoing/bbs/server/data/backups | head -5
```

## 输出格式

1. **一句话结论**：线上是否可以放心交给下一个人
2. **体检表**：进程 / 端口 / 证书 / 静态 / 备份 / 发布 / 网络，每项 通过 / 注意 / 失败
3. **回归记录**：核心流程每个动作的结果（含截图或命令输出）
4. **风险清单**：按「多久会出事」排序
5. **改进建议**：只列真正能落地的，按性价比排
6. **交接说明**：下一个接手的人必须知道的三件事

## 硬约束

- 重启服务前必须先确认没有正在跑的备份
- 恢复演练只在临时目录做，**绝不覆盖线上库**
- 不清理历史 APK（1.1G）除非被明确要求
- 不擅自改端口、域名、证书配置
- 发布动作只做验证性发布（例如同版本重发一次），不擅自升版本

---

# 通用规则（五段都适用）

1. **先有快照再动手。** 任何涉及数据库的段落，第一步都是 `db_snapshot.py` 存一份并 `--check`。
2. **只读优先。** 排查阶段不写库、不删文件、不重启。发现缺陷先报，等确认再修。
3. **一切结论要有证据。** 命令输出、SQL 结果、日志片段。没有证据的「可能」「也许」不算结论。
4. **区分「代码里能验」和「只有真机能验」。** 别混着写，否则下一个人会以为验过了。
5. **报告用中文，短句，先说结论。** 问题按 P0（数据错/安全/挂）> P1（功能不可用）> P2（体验）排序。
6. **不扩大战场。** 第 2 段不要顺手改 UI，第 4 段不要顺手改后端，跨段问题记下来交给对应段。
7. **改了就写清楚。** 如果被授权修复：改了哪个文件、哪一行、为什么、怎么验证、怎么回滚。
