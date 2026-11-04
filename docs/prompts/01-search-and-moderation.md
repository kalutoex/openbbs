# 提示词 01 · 搜索升级 + 内容安全

> 交给执行者的完整任务书。照做，别自由发挥。
> 代码根：`/vol1/1000/data/code/ongoing/bbs`（服务端 `server/`，Flutter 客户端 `openbbs/`）。

---

## 0. 背景与现状（先看，别猜）

- 服务端是 FastAPI，**JSON 接口全在 `server/app/api.py` 一个文件里**（约 2156 行），
  路由前缀 `/api`，依赖函数 `optional_user` / `require_user`（在 `api.py` 里，173–190 行附近）。
- 表结构在 `server/app/db.py`：
  - `SCHEMA`（建表）、`EXTRA_COLUMNS`（只加不删的补列清单）、`LATE_SCHEMA`（索引）。
  - `init()` 每次启动自动补列/补索引，**重复执行必须安全**。
  - 已有：`threads(id,title,body,user_id,created_at,updated_at,reply_count,view_count,is_good,is_top,agree_count,images,edited_at)`、
    `replies(id,thread_id,body,user_id,created_at,parent_id,agree_count,images,floor_no,edited_at)`、
    `users(id,name,nickname,handle,avatar,signature,level,is_admin,uid,email,...)`。
- 现有搜索接口（`api.py` 约 1448 行）：

```python
@router.get("/search")
def search(q: str = "", page: int = 1, c=Depends(get_conn), user=Depends(optional_user)):
    ...
    where = "(t.title LIKE ? OR t.body LIKE ?)"
    ...
    return {"items": [_brief(r, user) for r in rows], "page": page, "total": total}
```

  它只扫 `threads`，**搜不到用户、搜不到回复正文**；帖子多了是整表扫描。
- 上传接口 `POST /api/upload` 在 `api.py`，已有：base64 长度预检、`_sniff()` 判真实类型
  （只收 jpg/png/gif/webp）、5MB（动图 10MB）上限、按 sha256 前 2 位分目录落 `data/uploads/`、
  返回 `{"url": "/img/xx/<file>"}`。
- 客户端搜索页 `openbbs/lib/pages/search_page.dart`（297 行），调 `Api.get('/search', {...})`。
- 客户端 `openbbs/lib/api.dart` 里 `Api.get/post/patch/delete` 已封装，会自动带 token 和选路。

**不要动**：鉴权、黑名单、站点清单、`main.py` 的网页模板、`templates/`。

---

## 1. 目标 A · 搜索升级

### 1.1 数据层

在 `db.py` 的 `LATE_SCHEMA` 里加（FTS5 + trigram，SQLite ≥ 3.34 可用，本机 3.53）：

```sql
-- 帖子全文索引：trigram 支持中文子串（3 字起），2 字查询回退 LIKE
CREATE VIRTUAL TABLE IF NOT EXISTS threads_fts USING fts5(
  title, body, content='threads', content_rowid='id', tokenize='trigram'
);
CREATE VIRTUAL TABLE IF NOT EXISTS replies_fts USING fts5(
  body, content='replies', content_rowid='id', tokenize='trigram'
);
```

触发同步：**用显式 SQL 维护，不用 TRIGGER**（现有代码全在 Python 里写库，改一处漏一处更糟）。
在 `db.py` 新增两个函数：

```python
def fts_upsert_thread(c, tid):
    """threads 行变了就重灌这一行的索引。删了就先删索引。"""
def fts_upsert_reply(c, rid): ...
def fts_delete(kind, row_id): ...
```

实现方式用 FTS5 的 external content 惯用法：

```sql
INSERT INTO threads_fts(threads_fts, rowid, title, body)
SELECT 'delete', id, title, body FROM threads WHERE id=?;
INSERT INTO threads_fts(rowid, title, body) SELECT id, title, body FROM threads WHERE id=?;
```

（先 delete 再 insert，靠 `SELECT` 兜住"行已不存在"的情况。）

**首次启动回填**：`init()` 里判断 `SELECT count(*) FROM threads_fts` 是否落后于 `threads`，
落后就 `INSERT INTO threads_fts(threads_fts) VALUES('rebuild')` —— rebuild 是 FTS5 内置命令，
对 external content 表会重扫全表。同理 `replies_fts`。

### 1.2 写路径挂同步

以下每个写操作执行完、`commit()` 之前，调一次同步函数：

| 位置 | 调用 |
|---|---|
| `POST /threads` 建帖后 | `db.fts_upsert_thread(c, tid)` |
| `PATCH /t/{tid}` 编辑后 | 同上 |
| `DELETE /t/{tid}` 删帖后 | `db.fts_delete("thread", tid)` |
| `POST /t/{tid}/reply` 建回复后 | `db.fts_upsert_reply(c, rid)` |
| `PATCH /c/{cid}` 编辑回复后 | 同上 |
| `DELETE /c/{cid}` 删回复后 | `db.fts_delete("reply", cid)` |
| `POST /admin/user/{uid}/reset_pw` 之类不碰正文的 | 不用管 |

漏一处就是"改了搜不到"，验收里会查。

### 1.3 接口

`GET /api/search` 保持路径不变，**加参数、加返回段**，老客户端不传新参数照旧能用。

请求：

| 参数 | 类型 | 默认 | 说明 |
|---|---|---|---|
| `q` | str | "" | 关键词，前后空白去掉 |
| `page` | int | 1 | 从 1 开始 |
| `kind` | str | "thread" | `thread` / `reply` / `user` / `all` |
| `sort` | str | "recent" | `recent`（updated_at 倒序）/ `hot`（reply_count 倒序） |

返回：

```json
{
  "items": [ ...帖子 brief，同现有 _brief()... ],
  "replies": [ {"reply_id":1,"thread_id":2,"thread_title":"…","excerpt":"…","author":"…","handle":"…","created_at":0} ],
  "users":   [ {"id":1,"uid":1,"name":"…","nickname":"…","handle":"…","avatar":"…","signature":"…","level":1} ],
  "page": 1, "total": 0,
  "kind": "all", "took_ms": 3
}
```

规则：

1. `kind=thread` 时 `replies`/`users` 返回空数组（保持形状稳定，别省键）。
2. `kind=all` 时三段都查，各取前 `PER_PAGE` 条，`total` 是帖子命中数。
3. 关键词长度 **≥ 3** 走 FTS：

   ```sql
   SELECT rowid FROM threads_fts WHERE threads_fts MATCH ? ORDER BY rank
   ```
   MATCH 的串要把用户输入里的 `"` 剥掉、整体包成短语引用：`'"' + q.replace('"','') + '"'`，
   避免 `OR` `*` `(` 这些 FTS 语法被当操作符。命中后用 rowid 回表 JOIN `users` 取作者信息。
4. 关键词长度 **1–2** 回退现有 `LIKE` 逻辑（trigram 查不了 2 字）。
5. 用户搜索永远走 `LIKE`（`name` / `nickname` / `handle` 三列），不看 `kind` 之外的东西：
   `WHERE name LIKE ? OR nickname LIKE ? OR handle LIKE ?`，`LIMIT 20`。
6. 空 `q` 直接返回空三段，`total=0`，不查库。
7. `q` 长于 64 字截断到 64。

### 1.4 客户端

`lib/pages/search_page.dart`：

1. 顶部加三个筛选 chip：`帖子 / 回复 / 用户`（默认帖子）。切换时带 `kind` 重查。
2. `帖子` 结果维持现有卡片。
3. `回复` 结果一行一条：`帖子标题` 一行、`摘要` 一行灰字、右侧作者 @标识。
   点进去 → `ThreadPage(threadId: r.threadId)`，不需要滚到具体楼层。
4. `用户` 结果：头像 + 昵称 + `@handle` + 签名，点进去 → `UserPage(name)`。
5. 本地存最近 10 条搜索词（`SharedPreferences` key `search_history_v1`），未输入时展示，
   点一下填进输入框，长按可删单条，输入框右侧小字"清空"。
6. 文案全部走 `Lc.current.*`，`lib/l10n/app_zh.arb` 与 `app_en.arb` 各加对应 key，
   `test/l10n_test.dart` 会校验 key 对齐 —— 两边必须同时加。

---

## 2. 目标 B · 内容安全

### 2.1 敏感词

新增 `server/config/sensitive.txt`（**首次启动不存在就自动建，内容为下面这份注释模板**）：

```
# 一行一个词，# 开头是注释，空行忽略。
# 匹配是"包含"匹配，不分大小写（英文转小写比）。
# 站长在这里加词，服务端 60 秒内自动重新加载，不用重启。
```

新增 `server/app/words.py`：

```python
"""敏感词表 + 图片黑名单。文件改了自动重载，别重启服务。"""

def check(texts) -> str:
    """返回第一个命中的词，没命中返回空串。texts 是若干段文本的列表。"""

def blocked_image(digest) -> bool: ...
def block_image(digest): ...
```

细节：

- 词表缓存 `(mtime, compiled)`，**每次 check 前看一次 mtime**（stat 一次，便宜），变了就重编。
  不要用定时线程，多进程（IPv4/IPv6 两个实例）各自看各自的。
- 匹配：词表 ≤ 2000 条时用 `re.compile("|".join(map(re.escape, words)), re.I)`；
  查之前把文本转小写（正则已带 `re.I`，中文无所谓，英文靠它）。
- 空词表 → 直接返回空串，不要编一个匹配一切的正则。

拦截点（命中就 `raise HTTPException(400, "内容里有不允许的词：%s" % w)`）：

| 接口 | 查哪些字段 |
|---|---|
| `POST /api/threads` | `title`、`body` |
| `PATCH /api/t/{tid}` | `title`、`body` |
| `POST /api/t/{tid}/reply` | `body` |
| `PATCH /api/c/{cid}` | `body` |
| `PATCH /api/me` | `nickname`、`signature` |
| `POST /api/register` | `name` |
| 私信发送（另一份提示词里的 `/api/dm/{uid}`） | `body` |

**管理员（`is_admin`）放行**，方便站长发公告。判断用 `user["is_admin"]`，
所以检查要放在 `require_user` 之后。

### 2.2 图片黑名单

- 文件 `server/data/image_block.txt`，一行一个 sha256（64 位十六进制）。
- `upload` 里算完 `digest` 之后、落盘之前：`if words.blocked_image(digest): raise HTTPException(403, "这张图被站长禁了")`。
- 新增管理接口（`require_user` + 手动判 `is_admin`，风格照抄现有 `/admin/*`）：

```
POST /api/admin/image/block     body: {"url": "/img/ab/xxxx.jpg"}
POST /api/admin/image/unblock   body: {"url": "/img/ab/xxxx.jpg"}
GET  /api/admin/image/blocked   → {"items": [{"sha256": "...", "name": "xxxx.jpg"}]}
```

- 从 `url` 反推 sha256：文件名是 `digest[:20] + "." + ext`，**不是完整哈希**。
  所以 block 接口要么收完整 sha256（客户端拿不到），要么按 url 读文件现算哈希。
  **选后者**：`url` 必须以 `/img/` 开头，否则 400；路径拼到 `data/uploads/` 下要防 `..` 穿越
  （`os.path.realpath` 前缀校验），文件不存在 404，读出来 `hashlib.sha256(raw).hexdigest()` 写进文件。
- 删掉一张已上传的图不影响黑名单（黑名单存哈希，不存引用计数）。

### 2.3 注册人机校验

不引第三方、不接图形验证码库。用**算术题 + HMAC 签名**，无状态。

```
GET /api/register/challenge
→ {"id": "b7f3…", "question": "7 + 5 = ?", "sig": "…", "expires_in": 300}
```

做法：

- `a,b` 取 `secrets.randbelow(10)+1`、`secrets.randbelow(10)+1`；`answer = a+b`。
- `id` = `secrets.token_hex(8)`。
- `sig = hmac_sha256(AUTH_SECRET, id + "|" + str(answer) + "|" + str(exp))` 的前 32 个 hex 字符，
  `exp = int(time.time()) + 300`。
- 不落库。整个 payload 只回上面四个字段。
- `AUTH_SECRET` 复用 `server/data/jwt_key` 派生的密钥（`auth.py` 已有私钥读取，
  用 `hashlib.sha256(private_bytes + b"challenge").digest()` 当 HMAC key）。

`POST /api/register` 加两个**可选**字段 `challenge_id`、`challenge_answer`：

- 配置项 `auth.register_challenge`（布尔，默认 `true`）关闭时不校验，老客户端照旧能注册。
- 开启时：两个字段缺一个 → 400「先答个题」；`challenge_id` 解析不出 `exp` 或过期 → 400「题过期了，重新拉一道」；
  `sig` 重算不一致（说明编的）→ 400「校验失败」；答案不对 → 400「答案不对」。
- **解析 `exp` 的办法**：`id` 里别塞时间，改成把 `exp` 拼在 `challenge_id` 后面：
  `challenge_id = "<token8>.<exp>"`，签名覆盖 `"<token8>|answer|exp"`。这样服务端不用存表。

客户端 `login_page.dart` 的注册分支：

- 切到注册态时 `GET /register/challenge` 拉一道题，显示为一行输入框标签 `Lc.current.humanCheck`：
  「7 + 5 = ?」，下面一个数字输入框。
- 提交注册带 `challenge_id`、`challenge_answer`。
- 注册失败且 message 含「题过期」→ 自动重新拉题并清空答案框。
- `AppState.register(...)` 的签名（`lib/store.dart`）加两个可选具名参数，别破坏现有调用。

---

## 3. 测试与验收

### 3.1 服务端（必须全过）

```bash
cd /vol1/1000/data/code/ongoing/bbs/server
# 1. 建一个临时库，别碰真库
OPENBBS_DB=/tmp/t1.db python3 -c "from app import db; db.init(); print('ok')"
# 2. 起服务（另开一个终端或用 nohup）
OPENBBS_DB=/tmp/t1.db OPENBBS_PORT=18080 python3 -m uvicorn app.main:app --port 18080 &
```

逐条打：

```bash
B=http://127.0.0.1:18080/api
# 注册（带挑战）
curl -s $B/register/challenge
# 发帖 / 回复 / 改帖 各一次后：
curl -s "$B/search?q=测试帖标题&kind=thread" | head -c 300
curl -s "$B/search?q=回复里的词&kind=reply"
curl -s "$B/search?q=alice&kind=user"
curl -s "$B/search?q=测"            # 1 字 → 走 LIKE，要有结果
# 敏感词：往 config/sensitive.txt 写一行 FOO，等 60 秒或 mtime 变，再发一条含 FOO 的帖 → 400
# 重新建库 → 旧数据在 init() 后能搜到（rebuild 生效）
```

判定：

- 改过标题再搜**新标题能搜到、旧标题搜不到**（同步没漏）。
- 删帖后搜不到。
- 1 字、2 字、3 字查询都不报 500。
- 敏感词命中返回 400 且 message 里**带那个词**。
- 管理员发含敏感词的帖 **成功**。
- 关掉 `auth.register_challenge` 后不带挑战字段能正常注册。

### 3.2 客户端

```bash
cd /vol1/1000/data/code/ongoing/openbbs
source /vol1/1000/data/code/.fenv
flutter analyze          # 必须 0 error
flutter test             # 必须全绿，含 test/l10n_test.dart
```

### 3.3 收尾

- 在 `docs/PLAN-5-STEPS.md` 的进度表后**追加一节**「第 6 段 · 搜索与内容安全」，
  写：做了什么、验收结论、已知边界（trigram 只支持 ≥3 字、词表是包含匹配会误伤）。
- `待修清单.md` 里把临时跳过的小问题记上。

---

## 4. 红线

- **不要**改 `main.py` 的网页版表单流程（那是老入口，用的是同一张表）。
- **不要**给 `threads`/`replies` 加会破坏 `main.py` 读的列。
- **不要**引入新依赖（除了标准库与现有 `requirements.txt` 里已有的）。
- **不要**把真库（`server/data/forum.db`）拿来测试，一律 `OPENBBS_DB=/tmp/...`。
- 注释写中文，短句，跟现有风格一致；提交信息一句话说清做了什么。
