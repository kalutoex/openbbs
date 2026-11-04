# 提示词 02 · 私信 + 异地备份

> 交给执行者的完整任务书。照做，别自由发挥。
> 代码根：`/vol1/1000/data/code/ongoing/bbs`（服务端 `server/`，客户端 `openbbs/`）。

---

## 0. 背景与现状（先看，别猜）

- 服务端 FastAPI，**接口全在 `server/app/api.py`**（约 2156 行），前缀 `/api`。
  表结构在 `server/app/db.py`：`SCHEMA` / `EXTRA_COLUMNS` / `LATE_SCHEMA`，`init()` 幂等补列补索引。
- 鉴权：`auth.read_token()` 从请求头取 token 验 Ed25519 签名，`require_user` / `optional_user`
  依赖已带封禁拦截（403 + `blacklist.BANNED_MSG`）。**所有读写接口都要挂在 `optional_user` 或 `require_user` 上。**
- 通知表 `notifications(user_id, actor_id, kind, thread_id, reply_id, body, is_read, created_at)`，
  现有 kind：`reply` / `reply2` / `agree` / `follow` 之类。`GET /api/notifications` 返回
  `{"items": [...], "unread": N}`。
- 客户端：`openbbs/lib/api.dart` 封装 `Api.get/post/patch/delete(path, body)`；
  `lib/store.dart` 的 `AppState` 管全局状态与未读数；`lib/pages/notice_tab.dart` 是"消息"页；
  `lib/widgets/app_drawer.dart` 是抽屉导航；`lib/pages/user_page.dart` 是用户主页。
- 文案统走 `Lc.current.*`，`lib/l10n/app_zh.arb` 与 `lib/l10n/app_en.arb` 必须成对加 key，
  `test/l10n_test.dart` 会校验。
- 备份：`server/backup.sh`（cron `10 3 * * *`），硬编码 `ROOT`、`DEST=$ROOT/data/backups`、`KEEP=30`；
  流程 = `db_snapshot.py` 快照 → `--check` 自检 → 打 `uploads.tgz` → 整包 tar → 清理旧份。
  `_cfg.sh` 提供 `cfg <section> <key> [默认值]` 读 `config/site.json`。恢复脚本 `server/restore.sh`。
- 磁盘：`/vol1` 是**无冗余 linear 卷**，`/vol2` 是另一块大盘（3.6T，当前几乎空）。

**不要动**：鉴权实现、黑名单同步、站点登记、`main.py` 网页模板。

---

## 1. 目标 A · 私信

### 1.1 数据层（加到 `db.py` 的 `SCHEMA` 里，新表，不改旧表）

```sql
-- 一对一会话。a_id < b_id，靠这个唯一键保证两人的会话只有一条。
CREATE TABLE IF NOT EXISTS dm_threads (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  a_id       INTEGER NOT NULL,
  b_id       INTEGER NOT NULL,
  last_id    INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  UNIQUE(a_id, b_id)
);
CREATE TABLE IF NOT EXISTS dm_messages (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  thread_id  INTEGER NOT NULL,
  from_id    INTEGER NOT NULL,
  to_id      INTEGER NOT NULL,
  body       TEXT NOT NULL DEFAULT '',
  images     TEXT NOT NULL DEFAULT '[]',
  is_read    INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL
);
```

索引放 `LATE_SCHEMA`：

```sql
CREATE INDEX IF NOT EXISTS idx_dm_msg_thread ON dm_messages(thread_id, id DESC);
CREATE INDEX IF NOT EXISTS idx_dm_unread ON dm_messages(to_id, is_read);
CREATE UNIQUE INDEX IF NOT EXISTS idx_dm_pair ON dm_threads(a_id, b_id);
```

**位置注意**：`dm_threads` 的 `id` 是站内自增，不跨站同步；跨站私信不在本任务范围。

### 1.2 接口（全部 `require_user`）

统一约定：`uid` 参数用**站内 `users.id`**（跟 `/u/{name}`、`/t/{tid}` 的 id 口径一致），
不是主站 `uid` 字段。响应里的用户一律走 `user_json(row)`。

```
GET  /api/dm?page=1
     → {"items":[{"thread_id":1,"peer":{...user_json...},"last":"最后一句话",
                  "last_at":0,"unread":2,"last_from_me":false}],
        "page":1,"total":3}
     按 last_id 倒序；只列有消息的会话。

GET  /api/dm/{uid}?before_id=0&limit=30
     → {"peer":{...},"items":[{"id":9,"from_id":2,"to_id":5,"body":"…",
                               "images":["/img/…"],"img_sizes":[[800,600]],
                               "created_at":0,"is_read":true}],
        "has_more":true,"thread_id":1}
     首次进会话（before_id=0）返回最新 30 条，正序（老→新）返回，前端直接铺。
     before_id>0 时取该 id 之前的 30 条，同样正序。顺手把这批"别人发给我且未读"的标为已读。

POST /api/dm/{uid}
     body {"body":"…","images":["/img/…"]}
     → {"id":10,"thread_id":1,"created_at":0}
     1. 不能发给自己 → 400「不能给自己发私信」
     2. 对方不存在 → 404
     3. body 去空白后为空且 images 为空 → 400「说点什么」
     4. body 长度 > 2000 → 400「太长了，2000 字以内」
     5. images 最多 9 个，元素必须以 `/img/` 开头，否则 400
     6. 过敏感词（提示词 01 的 `words.check`），命中 400
     7. 会话不存在就建（a_id=min,b_id=max）；写消息；更新 `dm_threads.last_id`
     8. 同时往 `notifications` 插一条：`kind='dm'`、`user_id=对方`、`actor_id=我`、
        `body=''`（正文不进通知，避免泄露）、`thread_id=NULL`、`reply_id=NULL`

POST /api/dm/{uid}/read
     → {"ok":true,"unread":0}   把这个会话里对方发给我的全标已读

GET  /api/dm/unread
     → {"total":3}              给首页角标用；没登录时 401（前端自己兜）
```

**注意**：`notifications` 的 `kind='dm'` 会让现有 `/notifications` 列表多一类，
`notice_tab.dart` 里按 kind 分图标/文案，需要处理这个新值（没处理的就走默认分支，
点击时跳私信会话而不是帖子）。

### 1.3 客户端

新文件两个，页面风格照抄现有（`Scaffold` + `AppBar` + 下拉刷新 + `Skeleton` 占位）：

**`lib/pages/inbox_page.dart`（私信列表）**

- AppBar 标题 `Lc.current.messages`，右上刷新。
- 一行一个会话：头像（`Widgets/Avatar`）→ 昵称 + 最后一句（截断一行灰字）→ 右侧时间 + 未读红点（数字）。
- 空态：「还没有私信」+ 一句「在别人主页点"发私信"」。
- 点击进 `ChatPage(peer: ...)`。
- 列表返回后刷新未读（`AppState.instance.refreshDmUnread()`）。

**`lib/pages/chat_page.dart`（对话）**

- AppBar：对方头像 + 昵称，点昵称进 `UserPage`。
- 消息气泡：自己右侧主色，对方左侧灰底；时间小字；图片用 `PostImages` 那套（点开大图）。
- 上滑到顶加载更早（`scrollable_positioned_list` 已在依赖里，或简单监听 `ScrollController`）。
- 底部输入条：多行 TextField（最多 6 行）+ 图片按钮（复用 `gallery_picker_page.dart` 的选择器）
  + 发送按钮。发送中禁用，失败 toast 并保留输入。
- 进入时 `GET /dm/{uid}`，发出后本地追加、滚到底。
- 轮询：页面可见时每 15 秒拉一次 `GET /dm/{uid}`（只取最新一页），离开页面停。
  **别做长连接、别做 WebSocket**，这版就轮询。

**接入点**

1. `lib/widgets/app_drawer.dart`：在「消息」下面加「私信」一行，右侧显示未读数（>0 才显示）。
2. `lib/pages/user_page.dart`：非本人主页的按钮区加「发私信」（描边按钮，和"关注"并排）。
3. `lib/pages/notice_tab.dart`：顶部加一条入口「私信 · N 条未读」（N>0 才显示），点击进 `InboxPage`。
4. `lib/store.dart`：
   - 加 `ValueNotifier<int> dmUnread`，`refreshDmUnread()` 调 `GET /dm/unread`。
   - 登录后、`AppState.load()` 里拉一次；从 `InboxPage`/`ChatPage` 返回时再拉一次。
   - **未登录或被封禁时不要拉**（401/403 静默）。
5. 首页底部 tab 的 "消息" 角标数字 = 通知未读 + 私信未读（合并显示，别加第二个角标）。

### 1.4 私信的边界（明确不做）

- 不做群聊、不做撤回、不做已读回执给对方看、不做附件（只图片）、不做跨站私信。
- 不做消息推送（通知栏那条在"推送"那一项里，单独的任务）。

---

## 2. 目标 B · 异地备份

### 2.1 配置

`config/site.json` 的 `backup` 段加两个键（`docs/CONFIG.md` 同步补说明）：

```json
"backup": {
  "dir": "/vol1/1000/data/code/ongoing/bbs/server/data/backups",
  "keep": 30,
  "mirror_dir": "/vol2/1000/backup/bbs",
  "mirror_keep": 14
}
```

- `mirror_dir` 为空 = 不镜像（默认行为不变，别把没配的人搞挂）。
- `install.sh` 生成配置时**不要**替用户猜镜像路径，留空。

### 2.2 `backup.sh` 改造

1. 开头 `source "$ROOT/_cfg.sh"`，把 `DEST` / `KEEP` 从硬编码改成：
   ```bash
   DEST="$(cfg backup dir)"; DEST="${DEST:-$ROOT/data/backups}"
   KEEP="$(cfg backup keep)"; KEEP="${KEEP:-30}"
   MIRROR="$(cfg backup mirror_dir)"
   MKEEP="$(cfg backup mirror_keep)"; MKEEP="${MKEEP:-14}"
   ```
2. 主备份写完、清理完旧份之后，做镜像：
   - `MIRROR` 为空 → 打印「未配置异地镜像，跳过」并正常退出 0。
   - 目录不存在 → `mkdir -p`，失败算错误。
   - 复制用 `cp -a`（同机不同卷，不要 rsync，少一个依赖）。
   - 复制完**校验 sha256 一致**，不一致 → 删掉镜像里那份、打印错误、`exit 2`。
   - 清理镜像目录里的旧份，留 `MKEEP` 份。
   - 主备份目录的清理**不能**受镜像失败影响（镜像失败也只影响退出码）。
3. 日志行格式保持现有 `== 时间 开始/完成` 风格，新增行用 `[镜像] 写入 …`。

### 2.3 `restore.sh`

- 加参数 `--from-mirror`：从 `mirror_dir` 里挑最新一份恢复，日志里标明来源。
- 现有「先给当前数据留底」的逻辑不变。
- 找不到镜像文件时，列出镜像目录里实际有哪些文件再退出。

### 2.4 验证（必须真跑）

```bash
cd /vol1/1000/data/code/ongoing/bbs/server
bash -n backup.sh && bash -n restore.sh          # 语法
MIRROR=/tmp/mirror_test bash backup.sh           # 用临时镜像目录，别写真盘
ls -l /tmp/mirror_test | tail -3
sha256sum /tmp/mirror_test/*.tar.gz data/backups/*.tar.gz | sort   # 两边哈希要成对相同

# 不配镜像时行为不变
bash backup.sh && echo "exit=$?"

# 镜像目录不可写时要报错且主备份仍然成功
mkdir -p /tmp/ro && chmod 555 /tmp/ro
# 临时把 mirror_dir 指过去跑一次，确认退出码 2、主备份文件还在
```

最后**真的跑一次**（cron 是 `10 3 * * *`，别等明天）：

```bash
bash /vol1/1000/data/code/ongoing/bbs/server/backup.sh; echo "exit=$?"
tail -20 /vol1/1000/data/code/ongoing/bbs/server/logs/backup.log
ls -lh /vol2/1000/backup/bbs | tail -3
```

---

## 3. 验收清单

服务端：

- [ ] `OPENBBS_DB=/tmp/t2.db python3 -c "from app import db; db.init()"` 跑两次不报错（幂等）
- [ ] 两个账号互发、列表、分页、已读、未读数全对
- [ ] 发给自己 400；空消息 400；超长 400；对方不存在 404
- [ ] 被封账号调 `/api/dm` 得 403 且文案是「账号已被封禁」
- [ ] 敏感词能拦住私信
- [ ] `notifications` 里出现 `kind='dm'` 且 `body` 为空

客户端：

- [ ] `flutter analyze` 0 error；`flutter test` 全绿（含 l10n 对齐）
- [ ] 抽屉有「私信」、别人主页有「发私信」、消息页有入口
- [ ] 未读角标在发完/读完/返回后立刻变
- [ ] 切站后私信列表跟着换（走当前站的接口，不要串站）

备份：

- [ ] 主备份 + 镜像两份 sha256 一致
- [ ] 未配镜像时退出码 0
- [ ] 镜像不可写时退出码 2，主备份仍在
- [ ] `restore.sh --from-mirror` 能列出并恢复

文档：

- [ ] `docs/CONFIG.md` 补 `backup.mirror_dir` / `backup.mirror_keep`
- [ ] `docs/PLAN-5-STEPS.md` 追加「第 7 段 · 私信与异地备份」小节
- [ ] `待修清单.md` 记录临时跳过项

---

## 4. 红线

- 不引第三方依赖（`requirements.txt` 不新增）。
- 私信正文**不进通知表**（`notifications.body` 留空），避免绕开私信权限读到内容。
- 所有 `/api/dm/*` 必须过 `require_user`，读接口也不例外 —— 私信不是公开内容。
- 测试一律用 `OPENBBS_DB=/tmp/…`，不许拿 `server/data/forum.db` 试。
- 备份脚本改动后**必须真跑一次**并核对哈希，不许只过 `bash -n`。
- 注释中文、短句、跟现有风格一致。
