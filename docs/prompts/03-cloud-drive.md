# 提示词 03 · 用户云盘（10 段任务书）

> 交给执行者的完整任务书。照做，别自由发挥。
> 业务规则已由阿尔定死（见 0.1），**不要再问、不要改**。技术实现自己拿主意。
> 代码根：`/vol1/1000/data/code/ongoing/`
> 服务端 `bbs/server/`，客户端 `openbbs/`，另有一份服务端副本 `openbbs/server/`。

---

## 0. 背景与现状（先看，别猜）

- 服务端 FastAPI。接口全在 `server/app/api.py`，前缀 `/api`，鉴权用 `require_user` / `optional_user`。
- 表结构在 `server/app/db.py`：`SCHEMA`（建表）、`EXTRA_COLUMNS`（只加不删的补列）、`LATE_SCHEMA`（索引）。
  `init()` 每次启动幂等补列补索引，重复执行必须安全。**新表写进 SCHEMA，新列写进 EXTRA_COLUMNS。**
- 附件现状：
  - `files(digest PK, name, size, mime, uploader, created_at, downloads)` —— 一行一个内容，`uploader` 只记第一个人。
  - 物理文件 content-addressed：`data/files/<sha前2>/<sha前20>`，无扩展名。
  - `server/app/files.py`：`ingest()` 流式写盘 + 算 sha，超限中途掐断；`quota()` 按上传者求和。
  - 上传 `POST /api/file`（multipart），下载 `GET /f/{digest}`（公开，当附件吐，不内联）。
  - 帖子引用附件：`threads.files` / `replies.files` 存 JSON 数组。
- 限额已在 2026-11-05 取消：`limits.file_mb` / `files_per_day` / `files_mb_per_day` 全部为 0（0 = 不限）。
  `files_per_post` 仍是 5，那是帖子排版上限，**云盘不受它约束**。
- 客户端：`lib/pages/me_tab.dart`（第 175 行是「关注」那一项），`lib/api.dart`（所有接口调用），
  `lib/file_pick.dart` + `lib/file_open.dart`（选文件 / 打开下载，分 web 和 io 两份实现），
  `lib/widgets/file_card.dart`（附件卡，已有 `PostFileCard.height = 80` / `maxWidth = 420`）。
- 部署：客户端 `bash deploy_web.sh`（构建+部署+压缩+自检）；服务端 `bash run.sh`（重启 uvicorn，四个进程）。
- 测试：`flutter test`，现有 68 个，**必须全绿才算完**。

## 0.1 已定规则（阿尔拍板，不要改）

1. 注册送 5GB，老用户也补上。
2. 每人一个额度数字，后台随时能改（以后 VIP 就是把这个数字调大）。
3. 上传到帖子的文件**同时**进云盘；**删帖子不退空间**（文件还在云盘里）。
4. 云盘里删文件，空间**立刻**还回来。
5. 两个人传同一个文件，各算各的，互不影响。
6. 单文件不设死上限，只看剩余空间。
7. 传输中断就重传，**不做断点续传**。
8. 一次只能传一个文件，排队。
9. 空间满时的提示文案不能写死，要能改。
10. 删掉的文件进回收站，7 天内能捡回来。
11. 云盘文件列表**平铺**一长列，带搜索和排序；代码要留好以后加文件夹的口子。
12. 云盘文件**不能**塞进帖子。
13. 云盘文件**不能**改名。
14. 管理员能看到每个人的用量、能删文件，但看不到内容。
15. VIP 到期掉回 5GB 但已超额的：锁上传，文件不动。
16. **图片不占这 5GB**（图片走 `/api/upload`，那条链路不要碰）。
17. 删云盘文件时，如果帖子还在用它：允许删，删前提示「这个文件在 N 个帖子里用着」，删完帖子那边显示文件失效。
18. 分享链接不做；私人文件只有本人登录能下。
19. 封号、小号刷容量：**不管**，不要为这两件事写代码。

## 0.2 共同约定（每段都适用）

- **服务端改两处**：`bbs/server/app/*` 改完，同样改动同步到 `openbbs/server/app/*`。
  两份 `api.py` 已有分叉（约 500 行差异），**逐处手改，不要整文件覆盖**。
- 改完服务端：`cd bbs/server && bash run.sh`，`curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8080/api/feed` 要 200。
- 改完客户端：`flutter analyze` 零 error，`flutter test` 68 个全过，`bash deploy_web.sh` 部署。
- 每段做完提交一次 commit，信息写清楚做了什么。
- 不要顺手重构无关代码。不要动图片上传链路、不要动 `/api/upload` 的限额。

## 0.3 数据模型（第 2 段落地，后面都依赖它）

```sql
-- 每人一份文件清单，指向同一份物理文件。空间按这张表算。
CREATE TABLE IF NOT EXISTS user_files (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id    INTEGER NOT NULL,
  digest     TEXT    NOT NULL,
  name       TEXT    NOT NULL,
  size       INTEGER NOT NULL,
  source     TEXT    NOT NULL DEFAULT 'cloud',  -- cloud | post
  thread_id  INTEGER,                            -- source=post 时记来源帖
  public     INTEGER NOT NULL DEFAULT 0,         -- 1 = 帖子附件，外人可下
  created_at INTEGER NOT NULL,
  deleted_at INTEGER                             -- 非空 = 在回收站，不占额度
);
CREATE INDEX IF NOT EXISTS idx_user_files_owner  ON user_files(user_id, deleted_at, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_user_files_digest ON user_files(digest);

-- 额度：NULL 表示用全局默认（limits.cloud_quota_mb）
ALTER TABLE users ADD COLUMN quota_bytes INTEGER;
```

`files` 表继续留着，只当物理文件的元数据（大小、mime、下载次数）。**它的 uploader 不再是账本。**

---

## 进度表

| 段 | 内容 | 状态 |
|----|------|------|
| 1 | 存储搬到 /vol3 | 未开始 |
| 2 | 账本表 + 额度字段 + 历史回填 | 未开始 |
| 3 | 配额计算与上传校验 | 未开始 |
| 4 | 云盘接口（列表/用量/删除/回收站） | 未开始 |
| 5 | 私有下载鉴权 | 未开始 |
| 6 | 帖子附件接入账本 | 未开始 |
| 7 | 回收站清理任务 | 未开始 |
| 8 | 「我的」页容量卡 | 未开始 |
| 9 | 云盘页面 | 未开始 |
| 10 | 后台管理 + 配置收尾 + 回归 | 未开始 |

每做完一段，把状态改成「已完成 YYYY-MM-DD」，并写一句实际做了什么。

---

## 第 1 段 · 存储搬到 /vol3

**目标**：云盘的文件落 `/vol3`，老附件不丢。

**做**

1. `mkdir -p /vol3/cloud/files`
2. `rsync -a /vol1/1000/data/code/ongoing/bbs/server/data/files/ /vol3/cloud/files/`
   （注意结尾斜杠；带 `--one-file-system` 不必，这里同盘且目录小）
3. 在 `server/config/site.json` 的 `paths.files` 写 `/vol3/cloud/files`。**不改代码默认值**，路径属于部署配置。
4. 重启服务端，验证：
   - 老帖子附件 URL 仍 200
   - `curl -X POST -F file=@xx.txt -H "Authorization: Bearer <token>" http://127.0.0.1:8080/api/file` 落盘在 `/vol3/cloud/files/`
5. 确认 `data/files` 先别删，留一周。

**验收**：新传的文件在 `/vol3` 下；老附件能下载；`df -h /vol3` 正常。

**不做**：不动 `/vol1` 上的其它数据；不清理老目录。

---

## 第 2 段 · 账本表 + 额度字段 + 历史回填

**目标**：有地方记「谁存了什么」，空间能按人算。

**做**

1. `db.py`：`SCHEMA` 里加 `user_files` 表和两个索引（见 0.3）。
2. `db.py`：`EXTRA_COLUMNS` 加 `("users", "quota_bytes", "INTEGER")`。
3. 回填历史：`init()` 之后跑一次（写成幂等的回填函数，放 `db.py` 或新模块）：
   把现有 `files` 表每行转成一条 `user_files(user_id=uploader, source='cloud', public=0)`。
   已经回填过就跳过（`user_files` 非空且 digest 已存在则不再插）。
4. 顺带修正历史帖子的 `public`：扫 `threads.files` / `replies.files` 的 JSON，凡是出现在里面的 digest，
   把对应 `user_files.public` 置 1。老数据量很小，一次性扫完即可。

**验收**：`sqlite3 data/forum.db "select user_id,count(*),sum(size) from user_files group by user_id"` 有数；
现有 271K 附件都对得上；重启两次不重复插入。

**不做**：不改 `files` 表结构。

---

## 第 3 段 · 配额计算与上传校验

**目标**：超了 5GB 就传不上，提示能改。

**做**

1. `files.py` 加：
   - `quota_of(user)` → `user["quota_bytes"] or limits.cloud_quota_mb * 1024 * 1024`
   - `used(c, uid)` → `SUM(size) FROM user_files WHERE user_id=? AND deleted_at IS NULL`
   - `remaining(c, user)` → max(0, quota - used)
2. 配置 `config/site.json` + `config.py` 的 `DEFAULTS["limits"]` 加：
   - `cloud_quota_mb`: 5120
   - `cloud_trash_days`: 7
   - `cloud_full_msg`: `"空间不足，还差 {need}"`（占位符就这两个字面量，别换）
3. `POST /api/file`：把 `ingest(f, cap)` 的 cap 换成 `remaining()`（cap 为 0 或 None 时按不限处理，逻辑别写反）。
   传完写 `user_files`（source 由调用方标记，默认 `cloud`）。超限捕获 `TooBig` → `413`，body 用 `cloud_full_msg` 渲染。
4. **图片链路不碰**：`/api/upload` 一行都不改。

**验收**：造一个 `quota_bytes = 1MB` 的测试用户，传 2MB 文件被拒且提示文案正确；
传 500KB 成功，`used` 增加 500KB；把 `cloud_full_msg` 改个词重启，提示跟着变。

**不做**：不做并发锁（同时传两个可能略超，接受）；不做速率限制。

---

## 第 4 段 · 云盘接口（列表 / 用量 / 删除 / 回收站）

**目标**：客户端要的数据都有。

**做**（全部 `require_user`，只操作自己的记录）

- `GET /api/cloud/usage` → `{quota, used, count, trash}`（trash 是回收站里占的字节，仅供参考）
- `GET /api/cloud/files?q=&sort=time|size&page=1` → 分页列表，字段 `id, digest, name, size, created_at, source, refs`
  - `refs` = 这个文件被几个帖子用着（查 `threads.files`/`replies.files` JSON 命中数；数据量小，直接扫）
  - `q` 搜文件名；`sort` 默认 `time` 倒序
- `DELETE /api/cloud/files/{id}` → 设 `deleted_at`，**不删物理文件**
- `GET /api/cloud/trash` → 回收站列表（带剩余天数）
- `POST /api/cloud/files/{id}/restore` → 清空 `deleted_at`；空间不够时拒绝并说明

**验收**：用 curl 串一遍：传文件 → 列表能看到 → 删 → `usage.used` 立刻减少 → 回收站能看到 → 恢复 → `used` 回去。

**不做**：不做文件夹字段（但 SQL 里别把路径写死，以后加 `folder` 列要能加）；不做改名。

---

## 第 5 段 · 私有下载鉴权

**目标**：别人的云盘文件，链接拿到也下不了；帖子附件照旧公开。

**做**

1. `serve_file(digest)` 加判断，顺序如下：
   - `user_files` 里存在该 digest 且 `public=1` → 放行（帖子附件）
   - 否则要求登录（`optional_user`），且本人有该 digest 的未删除记录 → 放行
   - 都不满足 → `403`，文案「无权访问」
2. 响应头保持现状（`Content-Disposition: attachment`、`nosniff`），不要内联。
3. 下载计数照旧。

**验收**：A 传的私有文件，B 登录后拿 URL 打开 → 403；同一个文件被 A 发到帖子里（`public=1`）→ 匿名也能下；
A 自己 → 200。

**不做**：不做签名 URL / 时效链接。

---

## 第 6 段 · 帖子附件接入账本

**目标**：发帖带的文件也扣空间，并且出现在云盘里。

**做**

1. 发帖 / 回帖 / 编辑带附件时（`api.py` 里写 `threads.files` / `replies.files` 的三处），
   同时写 `user_files`：`source='post'`、`public=1`、`thread_id=帖子 id`。同一帖重复编辑不重复记。
2. 删帖子：**不动 `user_files`**（空间不退，文件仍在云盘）。这一点在代码里写一行注释，防止以后被人「修好」。
3. `files_per_post = 5` 保留，超了照旧拒绝。

**验收**：发一个带 2 个附件的帖 → 云盘列表出现这 2 个文件、`usage.used` 增加 → 删帖 → `used` 不变、
云盘里文件还在 → 在云盘删掉它 → 帖子详情里该附件显示「文件已失效」。

**不做**：不做云盘 → 帖子的反向引用（规则 12）。

---

## 第 7 段 · 回收站清理任务

**目标**：7 天后真删，空间和磁盘都回来。

**做**

1. `main.py` 的 startup 里起一个 `asyncio.create_task`，每小时跑一次（`await asyncio.sleep(3600)` 循环）。
2. 每次清理：
   - `user_files` 里 `deleted_at < now - cloud_trash_days*86400` 的行 → 删除记录
   - 删记录后，若该 digest 已无任何 `user_files` 引用 → 删物理文件 + `files` 表那行
3. 兜底：回收站总量超过配额时（有人反复传删），提前清最老的，直到回到配额内。
4. 任务出错不能让服务挂：整段 try/except，打日志继续下一轮。

**验收**：把某行 `deleted_at` 改成 8 天前 → 重启 → 记录和物理文件都没了；
故意让清理抛异常 → 服务照常运行。

**不做**：不做后台手动「立即清理」按钮（想要再加）。

---

## 第 8 段 · 「我的」页容量卡

**目标**：一眼看到还剩多少。

**做**

1. `lib/pages/me_tab.dart` 第 175 行「关注」那一项**之前**插一张卡。
2. 卡片内容：`云盘` + 进度条（已用/总量） + 右侧 `1.2G / 5G`；数据来自 `/api/cloud/usage`。
   加载失败就显示 `-- / --`，不要弹错误。
3. 点击 → 进云盘页（第 9 段的 `CloudPage`；这段还没做就先跳占位页）。
4. 格式化用客户端已有的字节格式化函数，没有就在 `lib/utils.dart` 加一个（GB 保留 1 位）。
5. 文案进 `lib/l10n`，别硬编码中文。

**验收**：Web 端进去能看到卡；传个文件再回来看数字变了；断网进去不崩。

**不做**：不在卡片上放上传按钮。

---

## 第 9 段 · 云盘页面

**目标**：能看、能传、能下、能删。

**做**

1. 新文件 `lib/pages/cloud_page.dart`。
2. 结构：
   - 顶部：搜索框 + 排序切换（时间/大小）
   - 列表：平铺一列，每行 = 图标 / 文件名（单行省略） / 大小 + 时间 / 右侧下载和删除
   - 右下角上传按钮：`file_pick` 选文件 → 一次一个 → 传完刷新
   - 底部或顶部入口：回收站
3. 删除：弹确认框；`refs > 0` 时在框里加一句「这个文件在 N 个帖子里用着，删了那边就失效」。
4. 下载：复用 `file_open.dart` 的现有逻辑。
5. 空列表给一句提示，别留白。
6. 分页：滚到底加载下一页。

**验收**：Web 端完整走一遍：上传 → 搜索 → 排序 → 下载 → 删除 → 回收站恢复；文件名很长不撑破布局；空列表有提示。

**不做**：不做文件夹、不做改名、不做多选批量删（先不做，代码别写死成不可能加）。

---

## 第 10 段 · 后台管理 + 配置收尾 + 回归

**目标**：能给 VIP 加额度，能收尾。

**做**

1. 管理员接口（`is_admin`）：
   - `GET /api/admin/cloud/usage?page=` → 所有人的 `{user_id, name, used, quota}`
   - `POST /api/admin/cloud/quota` `{user_id, quota_mb}` → 改额度（0 或 -1 表示用全局默认，自己定一种，写注释）
   - `DELETE /api/admin/cloud/file/{id}` → 删记录
2. 客户端：`admin_users_page.dart` 加「云盘用量」列 + 点进去能改额度。
3. 配置项全部落到 `config/site.json`：`cloud_quota_mb` / `cloud_trash_days` / `cloud_full_msg`。
   在 `docs/CONFIG.md` 补上这三项说明。
4. 回归：
   - `flutter analyze` 零 error，`flutter test` 68 个全过
   - `bash deploy_web.sh` 部署
   - 手工过一遍：注册新号 → 我的看到 5G → 传文件 → 发帖带附件 → 删帖空间不退 → 云盘删文件 → 回收站恢复
5. 更新本文档进度表，写清每段实际做了什么、哪些地方跟原计划不一样。

**验收**：后台能给某账号改到 20G 并生效；新号默认 5G；文档进度表全部完成。

**不做**：不做套餐 / 支付 / 自动降级逻辑，只留额度字段。

---

## 附：本段不做的清单（别自己加）

断点续传、分享链接、文件夹、改名、多选批量删除、图片计入额度、封号处理、小号风控、
套餐支付、跨用户转存。
