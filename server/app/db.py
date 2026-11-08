# -*- coding: utf-8 -*-
"""SQLite 存取。库文件放在 <项目>/server/data/（zfs 上的 WAL 多进程实测可用）。

表结构演进原则：**只加不删**。网页版（main.py）只用最初那几列，
App（api.py）用后加的列，两边共用一个库，谁也别去动对方的列。
"""
import hashlib
import json
import os
import random
import re
import sqlite3
import time

from . import config

# 库文件位置由 config 决定：默认 server/data/forum.db，
# 要起第二实例就设 OPENBBS_DB，两份代码各写各的库，互不影响。
DB = config.path("db")

SCHEMA = """
CREATE TABLE IF NOT EXISTS users (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  name        TEXT NOT NULL UNIQUE,
  pw          TEXT NOT NULL,
  created_at  INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS threads (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  title       TEXT NOT NULL,
  body        TEXT NOT NULL,
  user_id     INTEGER NOT NULL,
  created_at  INTEGER NOT NULL,
  updated_at  INTEGER NOT NULL,
  reply_count INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS replies (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  thread_id   INTEGER NOT NULL,
  body        TEXT NOT NULL,
  user_id     INTEGER NOT NULL,
  created_at  INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_replies_thread ON replies(thread_id, id);

-- 附件：文件本身在 data/files 里，这里只记名字、大小、谁传的。
CREATE TABLE IF NOT EXISTS files (
  digest     TEXT PRIMARY KEY,
  name       TEXT NOT NULL,
  size       INTEGER NOT NULL,
  mime       TEXT NOT NULL DEFAULT '',
  uploader   INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  downloads  INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_files_uploader ON files(uploader, created_at);

-- 云盘账本：每人一份文件清单，指向 files 里那份物理文件。
-- 空间按这张表算：deleted_at 为空的行才算占用。
-- files.uploader 只是「谁先传的」，不再是配额依据。
CREATE TABLE IF NOT EXISTS user_files (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id    INTEGER NOT NULL,
  digest     TEXT    NOT NULL,
  name       TEXT    NOT NULL,
  size       INTEGER NOT NULL,
  source     TEXT    NOT NULL DEFAULT 'cloud',
  thread_id  INTEGER,
  public     INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  deleted_at INTEGER
);
CREATE INDEX IF NOT EXISTS idx_user_files_owner ON user_files(user_id, deleted_at, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_user_files_digest ON user_files(digest);
CREATE INDEX IF NOT EXISTS idx_user_files_trash ON user_files(deleted_at) WHERE deleted_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_threads_updated ON threads(updated_at DESC);

CREATE TABLE IF NOT EXISTS likes (
  user_id     INTEGER NOT NULL,
  target_kind TEXT NOT NULL,
  target_id   INTEGER NOT NULL,
  created_at  INTEGER NOT NULL,
  PRIMARY KEY (user_id, target_kind, target_id)
);

-- 通知：回复、楼中楼、赞。接收者 user_id，触发者 actor_id。
CREATE TABLE IF NOT EXISTS notifications (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id    INTEGER NOT NULL,
  actor_id   INTEGER NOT NULL,
  kind       TEXT NOT NULL,
  thread_id  INTEGER,
  reply_id   INTEGER,
  body       TEXT NOT NULL DEFAULT '',
  is_read    INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_notif_user ON notifications(user_id, id DESC);

-- 私信：一对一会话。a_id < b_id，唯一键保证两个人只有一条会话。
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

-- 会话的个人状态：置顶、免打扰、从自己列表里删掉（只清列表，记录还在）。
-- hidden_upto 存删除那一刻的 last_id，之后有新消息 last_id 变大，会话自己就回来了。
CREATE TABLE IF NOT EXISTS dm_state (
  user_id     INTEGER NOT NULL,
  thread_id   INTEGER NOT NULL,
  pinned      INTEGER NOT NULL DEFAULT 0,
  muted       INTEGER NOT NULL DEFAULT 0,
  hidden_upto INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, thread_id)
);

-- 单条消息的「我这边删掉」。私信删一条只清自己，对方那边还在。
CREATE TABLE IF NOT EXISTS dm_msg_del (
  msg_id INTEGER NOT NULL,
  uid    INTEGER NOT NULL,
  PRIMARY KEY (msg_id, uid)
);

-- 举报：thread_id / reply_id 二选一，handled=0 表示待处理。
CREATE TABLE IF NOT EXISTS reports (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id    INTEGER NOT NULL,
  thread_id  INTEGER,
  reply_id   INTEGER,
  reason     TEXT NOT NULL DEFAULT '',
  handled    INTEGER NOT NULL DEFAULT 0,
  handled_by INTEGER,
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_reports_open ON reports(handled, id DESC);

CREATE TABLE IF NOT EXISTS favorites (
  user_id    INTEGER NOT NULL,
  thread_id  INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (user_id, thread_id)
);

CREATE TABLE IF NOT EXISTS follows (
  follower_id INTEGER NOT NULL,
  target_id   INTEGER NOT NULL,
  created_at  INTEGER NOT NULL,
  PRIMARY KEY (follower_id, target_id)
);

CREATE TABLE IF NOT EXISTS friends (
  user_id    INTEGER PRIMARY KEY,
  note       TEXT NOT NULL DEFAULT '',
  created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS history (
  user_id    INTEGER NOT NULL,
  thread_id  INTEGER NOT NULL,
  viewed_at  INTEGER NOT NULL,
  PRIMARY KEY (user_id, thread_id)
);

-- 注册验证码：一个邮箱只留最新一条，发新的覆盖旧的。
CREATE TABLE IF NOT EXISTS email_codes (
  email      TEXT PRIMARY KEY,
  code_hash  TEXT NOT NULL,
  expires_at INTEGER NOT NULL,
  sent_at    INTEGER NOT NULL,
  ip         TEXT,
  tries      INTEGER NOT NULL DEFAULT 0
);

-- 需求单：普通用户提「想要的新功能」，管理员在后台看。
-- status: 0 待看 / 1 采纳 / 2 不做
CREATE TABLE IF NOT EXISTS feature_requests (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id    INTEGER NOT NULL,
  title      TEXT NOT NULL,
  body       TEXT NOT NULL DEFAULT '',
  status     INTEGER NOT NULL DEFAULT 0,
  note       TEXT NOT NULL DEFAULT '',
  created_at INTEGER NOT NULL,
  handled_by INTEGER,
  handled_at INTEGER
);

-- 发码记录，只用来算频率，定期清。
CREATE TABLE IF NOT EXISTS email_sends (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  email      TEXT NOT NULL,
  ip         TEXT,
  created_at INTEGER NOT NULL
);

-- 全局黑名单。uid 是主站用户 id，跨站稳定。
-- 主站是权威；小站定时拉取后落在同一张表，synced_at 记拉到的时间。
-- banned=0 是解封的墓碑行：增量同步靠 ts 走，删掉行小站就永远学不到「解封」。
CREATE TABLE IF NOT EXISTS blacklist (
  uid        INTEGER PRIMARY KEY,
  ts         INTEGER NOT NULL,
  reason     TEXT NOT NULL DEFAULT '',
  synced_at  INTEGER NOT NULL DEFAULT 0,
  banned     INTEGER NOT NULL DEFAULT 1
);

-- 小站同步游标，只存最后拉到的 ts。
CREATE TABLE IF NOT EXISTS sync_state (
  key        TEXT PRIMARY KEY,
  value      TEXT NOT NULL DEFAULT ''
);

-- 站点目录（第 3 段）。主站存全部登记过的站，小站这张表空着不用。
-- 地址唯一：同一个地址换了 id 要报错，不然清单里会出现两座一样的站。
CREATE TABLE IF NOT EXISTS sites (
  site_id     TEXT PRIMARY KEY,
  name        TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  url         TEXT NOT NULL,
  endpoints   TEXT NOT NULL DEFAULT '[]',
  api         INTEGER NOT NULL DEFAULT 0,
  lang        TEXT NOT NULL DEFAULT '',
  icon        TEXT NOT NULL DEFAULT '',
  tags        TEXT NOT NULL DEFAULT '[]',
  open        INTEGER NOT NULL DEFAULT 1,
  contact     TEXT NOT NULL DEFAULT '',
  verified    INTEGER NOT NULL DEFAULT 0,
  created_at  INTEGER NOT NULL,
  updated_at  INTEGER NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_sites_url ON sites(url);
"""

# 依赖 ALTER 加出来的列，必须在补列之后才能建。
LATE_SCHEMA = """
-- 全文索引：trigram 能中文子串（3 字起），2 字查询回退 LIKE。
-- 正文在索引里再存一份。不用 external content：trigram + external content 下
-- 的 'delete' 命令在本地实测会报 database disk image is malformed，宁可多占点地方。
CREATE VIRTUAL TABLE IF NOT EXISTS threads_fts USING fts5(
  title, body, tokenize='trigram'
);
CREATE VIRTUAL TABLE IF NOT EXISTS replies_fts USING fts5(
  body, tokenize='trigram'
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_handle ON users(handle);
-- 浏览量按人计：同一个人对同一帖最多算 10 次，再多不涨。
CREATE TABLE IF NOT EXISTS thread_views (
  thread_id INTEGER NOT NULL,
  user_id   INTEGER NOT NULL,
  hits      INTEGER NOT NULL DEFAULT 0,
  last_at   INTEGER NOT NULL,
  PRIMARY KEY (thread_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_fr_status ON feature_requests(status, id DESC);
CREATE INDEX IF NOT EXISTS idx_fr_user ON feature_requests(user_id, id DESC);
CREATE INDEX IF NOT EXISTS idx_replies_parent ON replies(parent_id);
CREATE INDEX IF NOT EXISTS idx_dm_msg_thread ON dm_messages(thread_id, id DESC);
CREATE INDEX IF NOT EXISTS idx_dm_unread ON dm_messages(to_id, is_read);
CREATE INDEX IF NOT EXISTS idx_dm_last ON dm_threads(last_id DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email ON users(email) WHERE email IS NOT NULL;
-- 写请求的幂等回执：客户端带 X-Request-Id，60 秒内同一个 id 只执行一次，
-- 重试（超时换入口重发）拿回的是第一次的结果，不会发两条帖。
-- status=0 表示「已认领、还在跑」。body 存原始响应字节，回放时原样吐回去。
CREATE TABLE IF NOT EXISTS idem (
  key        TEXT PRIMARY KEY,
  created_at INTEGER NOT NULL,
  status     INTEGER NOT NULL DEFAULT 0,
  ctype      TEXT,
  body       BLOB
);
CREATE INDEX IF NOT EXISTS idx_idem_created ON idem(created_at);
"""

# (表, 列, 定义) —— 加列时往这里追加，init() 会自动补，重复执行安全。
EXTRA_COLUMNS = [
    ("users", "nickname", "TEXT"),
    ("users", "avatar", "TEXT"),
    ("users", "signature", "TEXT NOT NULL DEFAULT ''"),
    ("users", "level", "INTEGER NOT NULL DEFAULT 1"),
    ("users", "is_admin", "INTEGER NOT NULL DEFAULT 0"),
    ("users", "uid", "INTEGER"),
    # 密码版本号：改密码/踢掉所有设备时 +1，旧 token 随之作废。
    ("users", "pw_ver", "INTEGER NOT NULL DEFAULT 0"),
    ("threads", "view_count", "INTEGER NOT NULL DEFAULT 0"),
    ("threads", "is_good", "INTEGER NOT NULL DEFAULT 0"),
    ("replies", "parent_id", "INTEGER"),
    ("replies", "agree_count", "INTEGER NOT NULL DEFAULT 0"),
    ("threads", "agree_count", "INTEGER NOT NULL DEFAULT 0"),
    ("threads", "images", "TEXT NOT NULL DEFAULT '[]'"),
    ("replies", "images", "TEXT NOT NULL DEFAULT '[]'"),
    ("threads", "files", "TEXT NOT NULL DEFAULT '[]'"),
    ("replies", "files", "TEXT NOT NULL DEFAULT '[]'"),
    ("replies", "floor_no", "INTEGER NOT NULL DEFAULT 0"),
    ("users", "handle", "TEXT"),
    ("users", "cover", "TEXT NOT NULL DEFAULT ''"),
    # 粉丝/关注列表是否公开。默认公开，本人可在编辑资料里关掉。
    ("users", "show_follows", "INTEGER NOT NULL DEFAULT 1"),
    # 云盘额度（字节）。NULL = 用全局默认 limits.cloud_quota_mb，VIP 就是改这一列。
    ("users", "quota_bytes", "INTEGER"),
    # 编辑过的帖子记一下时间，界面上标「已编辑」
    ("threads", "edited_at", "INTEGER"),
    ("replies", "edited_at", "INTEGER"),
    # 置顶：列表里排最前
    ("threads", "is_top", "INTEGER NOT NULL DEFAULT 0"),
    # 主题色（0–350，跟客户端的色带同一套档位）。同时是身份色：
    # 气泡、头像圈、楼层都用它，所以必须存在账号上、能被别人读到。
    ("users", "hue", "INTEGER"),
    # 撤回：自己发的两分钟内可以收回，正文和图片清掉，双方都显示「已撤回」
    ("dm_messages", "recalled", "INTEGER NOT NULL DEFAULT 0"),
    # 楼层撤回：同上，只是楼层留着占位，不删行
    ("replies", "recalled", "INTEGER NOT NULL DEFAULT 0"),
    # 注册邮箱。老用户是 NULL，不补、不管。
    ("users", "email", "TEXT"),
    ("users", "email_verified", "INTEGER NOT NULL DEFAULT 0"),
    ("users", "reg_ip", "TEXT"),
    # 主站用户 id。主站自己等于 id；小站存影子行，靠它跟主站对齐。
    ("users", "master_uid", "INTEGER"),
    # 老库的黑名单表没有 banned 列，补上（1=封禁，0=解封墓碑）。
    ("blacklist", "banned", "INTEGER NOT NULL DEFAULT 1"),
    # 私信引用：指回同一会话里的另一条，0 表示不是引用。
    ("dm_messages", "reply_id", "INTEGER NOT NULL DEFAULT 0"),
    # 私信附件：和帖子附件同一种结构 [{url,name,size}]
    ("dm_messages", "files", "TEXT NOT NULL DEFAULT '[]'"),
    # 云盘文件是谁删的。NULL = 老记录（当时只有主人能删），按主人算。
    ("user_files", "deleted_by", "INTEGER"),
]

# 用户名太长不好看，handle 统一小写、字母数字下划线。
_HANDLE_BAD = re.compile(r"[^0-9a-zA-Z_]+")


def slug_handle(raw, cap=16):
    """把名字揉成一个能当 @标识 的候选，太短就用 u + 数字兜。"""
    s = _HANDLE_BAD.sub("_", (raw or "").strip().lower()).strip("_")[:cap]
    if len(s) < 3:
        s = "u" + hashlib.md5((raw or "").encode("utf-8")).hexdigest()[:7]
    return s


def unique_handle(c, raw, uid=None):
    """在库里找一个没人用的 handle；冲突就 base2、base3 往上加。"""
    base = slug_handle(raw)
    for i in range(0, 500):
        cand = base if i == 0 else "%s%d" % (base, i + 1)
        row = c.execute("SELECT id FROM users WHERE handle=?", (cand,)).fetchone()
        if row is None or (uid is not None and row["id"] == uid):
            return cand
    return "%s%d" % (base, os.getpid())


def random_hue(c):
    """给新账号抽一个主题色：0–350 的整数，尽量避开库里已有的颜色。

    色环首尾相接，距离按 min(d, 350-d) 算。先把够远的候选全筛出来再随机挑，
    人多到塞不下就一步步放宽阈值——随机本来就不保证唯一。
    """
    used = [r[0] for r in c.execute("SELECT hue FROM users WHERE hue IS NOT NULL")
            if isinstance(r[0], int)]
    for gap in (24, 18, 12, 6):
        ok = [h for h in range(0, 351)
              if all(min(abs(h - u), 350 - abs(h - u)) >= gap for u in used)]
        if ok:
            return random.choice(ok)
    return random.randint(0, 350)


def conn():
    # 连接在 FastAPI 线程池里创建、在另一个线程里使用，必须关掉线程归属检查
    c = sqlite3.connect(DB, timeout=10, check_same_thread=False)
    c.row_factory = sqlite3.Row
    c.execute("PRAGMA journal_mode=WAL")
    c.execute("PRAGMA synchronous=NORMAL")
    c.execute("PRAGMA foreign_keys=ON")
    return c


def _columns(c, table):
    return {r["name"] for r in c.execute("PRAGMA table_info(%s)" % table)}


def init():
    os.makedirs(os.path.dirname(DB), exist_ok=True)
    c = conn()
    try:
        _fresh_friends = not c.execute(
            "SELECT 1 FROM sqlite_master WHERE type='table' AND name='friends'").fetchone()
        c.executescript(SCHEMA)
        if _fresh_friends:
            # 关于页的致谢名单第一次建立：先把现有的人都挂上，之后由管理员增删。
            c.execute("INSERT OR IGNORE INTO friends (user_id, note, created_at) "
                      "SELECT id, '', CAST(strftime('%s','now') AS INTEGER) FROM users")
        # 板块这一层已经拿掉：发帖只认站（主站/小站），不再有 forums 表。
        for table, col, decl in EXTRA_COLUMNS:
            if col not in _columns(c, table):
                try:
                    c.execute("ALTER TABLE %s ADD COLUMN %s %s" % (table, col, decl))
                except sqlite3.OperationalError:
                    # 另一个进程（IPv4/IPv6 各一个）同时补了同一列，忽略
                    pass
        c.executescript(LATE_SCHEMA)
        # 帖子回收站：结构直接照抄 threads，再加「什么时候删的、谁删的」。
        # 用 CTAS 建而不是手抄字段，以后 threads 加列这里自动跟上。
        if not c.execute("SELECT 1 FROM sqlite_master WHERE type='table' "
                         "AND name='thread_trash'").fetchone():
            c.execute("CREATE TABLE thread_trash AS SELECT * FROM threads WHERE 0")
            c.execute("ALTER TABLE thread_trash ADD COLUMN deleted_at INTEGER")
            c.execute("ALTER TABLE thread_trash ADD COLUMN deleted_by INTEGER")
        c.execute("CREATE INDEX IF NOT EXISTS idx_thread_trash_by "
                  "ON thread_trash(deleted_by, deleted_at DESC)")
        c.execute("CREATE INDEX IF NOT EXISTS idx_thread_trash_age "
                  "ON thread_trash(deleted_at)")
        # 云盘账本：老附件补记录，帖子引用过的标公开。幂等。
        backfill_user_files(c)
        # 全文索引落后就整体重建（老库第一次启动会走到这里）。
        # 没有 fts5 的 SQLite 会让上面的建表语句直接失败，所以这里也兜一层。
        try:
            if c.execute("SELECT count(*) FROM threads_fts").fetchone()[0] != \
                    c.execute("SELECT count(*) FROM threads").fetchone()[0]:
                c.execute("DELETE FROM threads_fts")
                c.execute("INSERT INTO threads_fts(rowid, title, body) "
                          "SELECT id, title, body FROM threads")
            if c.execute("SELECT count(*) FROM replies_fts").fetchone()[0] != \
                    c.execute("SELECT count(*) FROM replies").fetchone()[0]:
                c.execute("DELETE FROM replies_fts")
                c.execute("INSERT INTO replies_fts(rowid, body) SELECT id, body FROM replies")
        except sqlite3.OperationalError:
            pass
        # 板块这一层拿掉了：老库里的 forums / forum_follows 和 threads.forum_id
        # 一并收走。帖子不再带归属字段，全部算主站的。新库上这三步都是空转。
        if c.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='forums'").fetchone():
            c.execute("DROP TABLE IF EXISTS forum_follows")
            c.execute("DROP TABLE IF EXISTS forums")
        if "forum_id" in _columns(c, "threads"):
            try:
                c.execute("DROP INDEX IF EXISTS idx_threads_forum")
                c.execute("ALTER TABLE threads DROP COLUMN forum_id")
            except sqlite3.OperationalError:
                # SQLite 太老删不了列：留着也没人读，不碍事
                pass
        # 老用户补 @标识：昵称/用户名揉一个，冲突自动加序号
        for r in c.execute("SELECT id, name, nickname FROM users WHERE handle IS NULL OR handle=''"):
            c.execute("UPDATE users SET handle=? WHERE id=?",
                      (unique_handle(c, r["nickname"] or r["name"], r["id"]), r["id"]))
        # 注册序号：老库按注册时间重排一遍，之后注册只往后加，删号也不回收。
        if c.execute("SELECT 1 FROM users WHERE uid IS NULL LIMIT 1").fetchone():
            c.execute(
                "UPDATE users SET uid=("
                "  SELECT COUNT(*) FROM users u2 WHERE u2.created_at<users.created_at "
                "  OR (u2.created_at=users.created_at AND u2.id<=users.id)"
                ")")
        # 老数据补楼层号：只给主楼层排，楼中楼保持 0
        if c.execute("SELECT 1 FROM replies WHERE COALESCE(parent_id,0)=0 AND floor_no=0 LIMIT 1").fetchone():
            c.execute(
                "UPDATE replies SET floor_no=("
                "  SELECT COUNT(*) + 1 FROM replies r2 WHERE r2.thread_id=replies.thread_id "
                "  AND COALESCE(r2.parent_id,0)=0 AND r2.id<=replies.id"
                ") WHERE COALESCE(parent_id,0)=0 AND floor_no=0")
        c.commit()
    finally:
        c.close()


# ---------------------------------------------------------------- 全文索引同步
#
# 全量先按 rowid 删再插。FTS5 普通表支持 DELETE ... WHERE rowid=?，幂等。
# 删行要在真删之前调 fts_delete —— 虽然这里只需要 rowid，早调晚调都行，但统一放前面。

def fts_upsert_thread(c, tid):
    try:
        c.execute("DELETE FROM threads_fts WHERE rowid=?", (tid,))
        c.execute("INSERT INTO threads_fts(rowid, title, body) "
                  "SELECT id, title, body FROM threads WHERE id=?", (tid,))
    except sqlite3.OperationalError:
        pass


def fts_upsert_reply(c, rid):
    try:
        c.execute("DELETE FROM replies_fts WHERE rowid=?", (rid,))
        c.execute("INSERT INTO replies_fts(rowid, body) "
                  "SELECT id, body FROM replies WHERE id=?", (rid,))
    except sqlite3.OperationalError:
        pass


def fts_delete(c, kind, row_id):
    """kind: thread / reply。必须在真删之前调。"""
    try:
        if kind == "thread":
            c.execute("DELETE FROM threads_fts WHERE rowid=?", (row_id,))
        else:
            c.execute("DELETE FROM replies_fts WHERE rowid=?", (row_id,))
    except sqlite3.OperationalError:
        pass


# ---------------------------------------------------------------- 云盘账本回填

# 老库里 files 表的每一行补一条账本记录。走 WHERE NOT EXISTS，跑多少遍都安全。
_BACKFILL_USER_FILES = """
INSERT INTO user_files(user_id, digest, name, size, source, public, created_at)
SELECT f.uploader, f.digest, f.name, f.size, 'cloud', 0, f.created_at
FROM files f
JOIN users u ON u.id = f.uploader
WHERE NOT EXISTS (
  SELECT 1 FROM user_files uf WHERE uf.user_id = f.uploader AND uf.digest = f.digest
)
"""


def _digest_of(item):
    """/f/<20位hex> → digest。认不出来就当没有。"""
    if not isinstance(item, dict):
        return None
    url = str(item.get("url") or "")
    m = re.search(r"/f/([0-9a-f]{20})$", url)
    return m.group(1) if m else None


def backfill_user_files(c):
    """把 files 表补进账本，并把帖子引用过的文件标成公开。

    每次启动跑一遍，代价是扫一遍 files 表（行数 = 物理文件数，很小）。
    帖子表的扫描只在有附件时才走，量也小。
    """
    try:
        c.execute(_BACKFILL_USER_FILES)
        digests = set()
        for table in ("threads", "replies"):
            for row in c.execute(
                    "SELECT files FROM %s WHERE files IS NOT NULL AND files LIKE '%%/f/%%'" % table):
                try:
                    items = json.loads(row["files"])
                except Exception:
                    continue
                if not isinstance(items, list):
                    continue
                for it in items:
                    d = _digest_of(it)
                    if d:
                        digests.add(d)
        for d in digests:
            c.execute("UPDATE user_files SET public=1 WHERE digest=?", (d,))
        c.commit()
    except sqlite3.OperationalError:
        pass


def purge_thread_trash(c, days=7):
    """清过期的帖子回收站记录，返回删掉的条数。

    帖子被删时，回复、点赞、通知、收藏、历史、搜索索引都已经清过了，
    所以这里只要把回收站里那行扔掉就行。
    """
    try:
        days = int(days)
    except (TypeError, ValueError):
        days = 7
    if days < 0:
        days = 0
    cutoff = int(time.time()) - days * 86400
    rows = c.execute("SELECT id FROM thread_trash WHERE deleted_at <= ?",
                     (cutoff,)).fetchall()
    if not rows:
        return 0
    ids = [r["id"] for r in rows]
    for i in range(0, len(ids), 400):
        chunk = ids[i:i + 400]
        c.execute("DELETE FROM thread_trash WHERE id IN (%s)" % ",".join("?" * len(chunk)), chunk)
    c.commit()
    return len(ids)
