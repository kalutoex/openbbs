# -*- coding: utf-8 -*-
"""SQLite 存取。库文件放在 <项目>/server/data/（zfs 上的 WAL 多进程实测可用）。

表结构演进原则：**只加不删**。网页版（main.py）只用最初那几列，
App（api.py）用后加的列，两边共用一个库，谁也别去动对方的列。
"""
import hashlib
import os
import re
import sqlite3

# 默认走生产库；设 BBS_DB 可以指到测试库，用来起第二实例（26017）联调，
# 两边共用同一份代码、各写各的库，互不影响。
DB = os.environ.get(
    "BBS_DB", "/vol1/1000/data/code/ongoing/bbs/server/data/forum.db")

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
CREATE INDEX IF NOT EXISTS idx_threads_updated ON threads(updated_at DESC);

CREATE TABLE IF NOT EXISTS forums (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  name         TEXT NOT NULL UNIQUE,
  title        TEXT NOT NULL DEFAULT '',
  intro        TEXT NOT NULL DEFAULT '',
  avatar       TEXT NOT NULL DEFAULT '',
  owner_id     INTEGER,
  created_at   INTEGER NOT NULL,
  thread_count INTEGER NOT NULL DEFAULT 0,
  follow_count INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS forum_follows (
  user_id    INTEGER NOT NULL,
  forum_id   INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (user_id, forum_id)
);
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
"""

# 依赖 ALTER 加出来的列，必须在补列之后才能建。
LATE_SCHEMA = """
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_handle ON users(handle);
CREATE INDEX IF NOT EXISTS idx_threads_forum ON threads(forum_id, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_fr_status ON feature_requests(status, id DESC);
CREATE INDEX IF NOT EXISTS idx_fr_user ON feature_requests(user_id, id DESC);
CREATE INDEX IF NOT EXISTS idx_replies_parent ON replies(parent_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email ON users(email) WHERE email IS NOT NULL;
"""

# (表, 列, 定义) —— 加列时往这里追加，init() 会自动补，重复执行安全。
EXTRA_COLUMNS = [
    ("users", "nickname", "TEXT"),
    ("users", "avatar", "TEXT"),
    ("users", "signature", "TEXT NOT NULL DEFAULT ''"),
    ("users", "level", "INTEGER NOT NULL DEFAULT 1"),
    ("users", "is_admin", "INTEGER NOT NULL DEFAULT 0"),
    ("users", "uid", "INTEGER"),
    ("threads", "forum_id", "INTEGER"),
    ("threads", "view_count", "INTEGER NOT NULL DEFAULT 0"),
    ("threads", "is_good", "INTEGER NOT NULL DEFAULT 0"),
    ("replies", "parent_id", "INTEGER"),
    ("replies", "agree_count", "INTEGER NOT NULL DEFAULT 0"),
    ("threads", "agree_count", "INTEGER NOT NULL DEFAULT 0"),
    ("threads", "images", "TEXT NOT NULL DEFAULT '[]'"),
    ("replies", "images", "TEXT NOT NULL DEFAULT '[]'"),
    ("replies", "floor_no", "INTEGER NOT NULL DEFAULT 0"),
    ("users", "handle", "TEXT"),
    ("users", "cover", "TEXT NOT NULL DEFAULT ''"),
    # 编辑过的帖子记一下时间，界面上标「已编辑」
    ("threads", "edited_at", "INTEGER"),
    ("replies", "edited_at", "INTEGER"),
    # 置顶：列表里排最前
    ("threads", "is_top", "INTEGER NOT NULL DEFAULT 0"),
    # 注册邮箱。老用户是 NULL，不补、不管。
    ("users", "email", "TEXT"),
    ("users", "email_verified", "INTEGER NOT NULL DEFAULT 0"),
    ("users", "reg_ip", "TEXT"),
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
        for table, col, decl in EXTRA_COLUMNS:
            if col not in _columns(c, table):
                try:
                    c.execute("ALTER TABLE %s ADD COLUMN %s %s" % (table, col, decl))
                except sqlite3.OperationalError:
                    # 另一个进程（IPv4/IPv6 各一个）同时补了同一列，忽略
                    pass
        c.executescript(LATE_SCHEMA)
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
