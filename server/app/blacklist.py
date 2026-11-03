# -*- coding: utf-8 -*-
"""全局黑名单。

C3 定了 token 不过期，封号就没法靠过期生效，只能在接口层拦 ——
这个模块就是那个兜底，不是可选项。

两种角色，同一份代码：

  主站  admin 封号 → 写 blacklist 表 → /api/blacklist?since= 增量发布。
        条目列表用主站 Ed25519 私钥签名，小站必须验签才收。

  小站  后台线程每 auth.blacklist_pull_seconds 秒拉一次，
        验签通过才落本地表。断网就拉不动，已有的封禁照样生效。

拦截在 api.optional_user / require_user 里，读接口也拦。
"""
import json
import threading
import time
import urllib.request

from . import auth, config, db

BANNED_MSG = "账号已被封禁"


# ---------------------------------------------------------------- 主站：写

def ban(c, uid: int, reason: str = "") -> int:
    ts = int(time.time())
    c.execute("INSERT INTO blacklist(uid, ts, reason, banned) VALUES(?,?,?,1) "
              "ON CONFLICT(uid) DO UPDATE SET ts=excluded.ts, reason=excluded.reason, banned=1",
              (int(uid), ts, reason or ""))
    c.commit()
    return ts


def unban(c, uid: int) -> None:
    """不删行，只置 banned=0 —— 删了小站就永远收不到「解封」这条增量。"""
    c.execute("UPDATE blacklist SET banned=0, ts=? WHERE uid=?",
              (int(time.time()), int(uid)))
    c.commit()


def is_banned(c, uid) -> bool:
    if not uid:
        return False
    row = c.execute("SELECT banned FROM blacklist WHERE uid=?", (int(uid),)).fetchone()
    return bool(row and row["banned"])


# ---------------------------------------------------------------- 主站：发布

def _canon(items) -> bytes:
    """签名对象：条目规范化 JSON。两端必须算得一模一样。"""
    return json.dumps(items, sort_keys=True, separators=(",", ":")).encode("utf-8")


def export_since(c, since: int = 0):
    """增量导出。ts 用封禁时间，客户端拿 last_ts 回填 since。"""
    rows = c.execute(
        "SELECT uid, ts, reason, banned FROM blacklist WHERE ts>? ORDER BY ts, uid",
        (int(since),)).fetchall()
    items = [{"uid": r["uid"], "ts": r["ts"], "banned": 1 if r["banned"] else 0,
              "reason": r["reason"] or ""} for r in rows]
    return {
        "items": items,
        "ts": int(time.time()),
        "sig": auth.sign_bytes(_canon(items)),
    }


# ---------------------------------------------------------------- 小站：拉

def _state_get(c, key: str) -> str:
    row = c.execute("SELECT value FROM sync_state WHERE key=?", (key,)).fetchone()
    return row["value"] if row else ""


def _state_set(c, key: str, value: str) -> None:
    c.execute("INSERT INTO sync_state(key,value) VALUES(?,?) "
              "ON CONFLICT(key) DO UPDATE SET value=excluded.value", (key, str(value)))
    c.commit()


def pull_once(pub_pem: str = "", master_url: str = "", timeout: int = 10) -> int:
    """拉一次增量，验签通过才落库。返回新增条数；任何异常都吞掉，别让线程死。"""
    master_url = (master_url or config.get("site", "master_url") or "").rstrip("/")
    if not master_url:
        return 0
    c = db.conn()
    try:
        since = int(_state_get(c, "blacklist_since") or 0)
        url = "%s/api/blacklist?since=%d" % (master_url, since)
        req = urllib.request.Request(url, headers={"accept": "application/json"})
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            data = json.loads(resp.read().decode("utf-8"))
        items = data.get("items") or []
        if items and not auth.verify_bytes(_canon(items), data.get("sig", ""), pub_pem):
            # 没签对就是没签对，一条都不收。
            return 0
        now = int(time.time())
        for it in items:
            c.execute(
                "INSERT INTO blacklist(uid, ts, reason, synced_at, banned) VALUES(?,?,?,?,?) "
                "ON CONFLICT(uid) DO UPDATE SET ts=excluded.ts, reason=excluded.reason, "
                "synced_at=excluded.synced_at, banned=excluded.banned",
                (int(it["uid"]), int(it["ts"]), it.get("reason") or "", now,
                 1 if it.get("banned", 1) else 0))
        if items:
            _state_set(c, "blacklist_since", max(int(it["ts"]) for it in items))
        _state_set(c, "blacklist_pull_at", now)
        return len(items)
    except Exception:
        return 0
    finally:
        c.close()


def fetch_public_key(master_url: str, timeout: int = 10) -> str:
    """小站第一次从主站 /meta 取公钥。取不到就空着，下次再试。"""
    master_url = (master_url or "").rstrip("/")
    if not master_url:
        return ""
    try:
        with urllib.request.urlopen(master_url + "/api/meta", timeout=timeout) as resp:
            data = json.loads(resp.read().decode("utf-8"))
        return data.get("public_key") or ""
    except Exception:
        return ""


# ---------------------------------------------------------------- 小站：后台线程

_started = False
_lock = threading.Lock()


def start_puller() -> None:
    """是主站就不起线程：主站直接读自己的表。"""
    global _started
    master_url = config.get("site", "master_url") or ""
    if not master_url:
        return
    with _lock:
        if _started:
            return
        _started = True

    interval = int(config.get("auth", "blacklist_pull_seconds", 60) or 60)
    pub_pem = config.get("auth", "public_key") or ""

    # 先把公钥拿到手：没有它，主站签的 token 在这台机器上验不过。
    if not pub_pem:
        pub_pem = fetch_public_key(master_url, timeout=5)
        if pub_pem:
            auth.set_master_pub(pub_pem)

    def loop():
        nonlocal pub_pem
        while True:
            try:
                if not pub_pem:
                    pub_pem = fetch_public_key(master_url)
                    if pub_pem:
                        auth.set_master_pub(pub_pem)
                pull_once(pub_pem, master_url)
            except Exception:
                pass
            time.sleep(max(10, interval))

    threading.Thread(target=loop, name="blacklist-puller", daemon=True).start()


def status() -> dict:
    """给 /meta 和排查用。"""
    c = db.conn()
    try:
        n = c.execute("SELECT COUNT(*) AS n FROM blacklist WHERE banned=1").fetchone()["n"]
        return {
            "role": "master" if not (config.get("site", "master_url") or "") else "slave",
            "banned": n,
            "last_pull": int(_state_get(c, "blacklist_pull_at") or 0),
            "since": int(_state_get(c, "blacklist_since") or 0),
        }
    finally:
        c.close()
