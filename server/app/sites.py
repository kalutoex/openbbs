# -*- coding: utf-8 -*-
"""第 3 段：站点自述与站点清单。

每个站都能自述（`/meta`、`/.well-known/bbs.json`），客户端拿域名就能认。
主站另存一份目录（`sites` 表），新站填了 `master_url` 就自己去登记拿 `site_id`，
不需要人肉分配。

清单格式见 docs/bbs.json.example，校验只有三条：
id 去重、缺地址丢弃、版本过高禁入。
"""
import hashlib
import ipaddress
import json
import re
import socket
import threading
import time
import urllib.parse
import urllib.request

from . import config, db

# 清单格式版本。字段含义变了才动它，加字段不动。
SCHEMA = 1

# 接口版本。/meta 里的 `api` 就是这个：客户端拿它决定能不能用新东西。
# 1 → 最初（帖子、用户）
# 2 → 站点自述 / 清单 / 登记（第 3 段）
API_VERSION = 2

_SITE_ID = re.compile(r"^[a-z0-9][a-z0-9-]{1,31}$")
_BAD_SLUG = re.compile(r"[^a-z0-9]+")

# 回访小站的天花板：慢站不能把主站拖住。
FETCH_TIMEOUT = 5
FETCH_LIMIT = 64 * 1024


class ConflictError(ValueError):
    """查重失败：id 或地址已经被别的站占了。"""


_reg_lock = threading.Lock()
_reg_hits = {}


def allow_register(ip: str) -> bool:
    """登记接口的粗限速。同一 IP 一小时超过阈值就拒。0 = 不限。"""
    per_hour = int(config.get("sites", "register_per_hour_ip", 10) or 0)
    if per_hour <= 0:
        return True
    now = int(time.time())
    with _reg_lock:
        arr = [t for t in _reg_hits.get(ip, []) if now - t < 3600]
        if len(arr) >= per_hour:
            _reg_hits[ip] = arr
            return False
        arr.append(now)
        _reg_hits[ip] = arr
    return True


# ---------------------------------------------------------------- 本机自述

def site_id() -> str:
    """配置里的 id 优先；小站自动登记拿到的那个存在库里，进程重启还在。"""
    sid = str(config.get("site", "site_id") or "").strip().lower()
    if sid:
        return sid
    c = db.conn()
    try:
        row = c.execute("SELECT value FROM sync_state WHERE key='assigned_site_id'").fetchone()
        return (row["value"] if row else "") or ""
    except Exception:
        return ""
    finally:
        c.close()


def _icon_url(base: str) -> str:
    icon = str(config.get("site", "icon") or "").strip()
    if not icon:
        return ""
    if icon.startswith("http://") or icon.startswith("https://"):
        return icon
    if base:
        return base.rstrip("/") + "/" + icon.lstrip("/")
    return icon


def _endpoints(base: str) -> list:
    """站点自己配的入口；没配就把 base_url 当成唯一入口。"""
    raw = config.get("site", "endpoints") or []
    out = []
    for it in raw:
        if isinstance(it, str) and it.strip():
            out.append({"url": it.strip().rstrip("/"), "note": ""})
        elif isinstance(it, dict) and str(it.get("url") or "").strip():
            out.append({"url": str(it["url"]).strip().rstrip("/"),
                        "note": str(it.get("note") or "")})
    if not out and base:
        out.append({"url": base.rstrip("/"), "note": "主入口"})
    return out


def self_site() -> dict:
    """本机的一条清单条目，`/meta` 和 `/.well-known/bbs.json` 共用。"""
    base = str(config.get("site", "base_url") or "").strip().rstrip("/")
    return {
        "id": site_id(),
        "name": str(config.get("site", "name") or ""),
        "description": str(config.get("site", "description") or ""),
        "url": base,
        "endpoints": _endpoints(base),
        "api": API_VERSION,
        "lang": str(config.get("site", "lang") or "zh-Hans"),
        "icon": _icon_url(base),
        "tags": [str(t) for t in (config.get("site", "tags") or []) if str(t).strip()],
        "open": bool(config.get("site", "open", True)),
        "contact": str(config.get("site", "contact") or ""),
        "updated": time.strftime("%Y-%m-%d", time.localtime()),
    }


def well_known() -> dict:
    """`/.well-known/bbs.json`：单站自述，sites 永远一条。

    客户端在这里读到的就是这座站的完整身份，不用先猜接口版本。
    """
    return {
        "schema": SCHEMA,
        "generated": time.strftime("%Y-%m-%dT%H:%M:%S%z", time.localtime()),
        "sites": [self_site()],
    }


# ---------------------------------------------------------------- 清单校验

def slug(text: str) -> str:
    s = _BAD_SLUG.sub("-", (text or "").strip().lower()).strip("-")[:24]
    # 清单 id 至少两位。全中文的站名转不出可读的 slug，用短哈希兜底，
    # 保证同名/同义的站不会挤到同一个 id 上。
    if len(s) >= 2:
        return s
    return "site-" + hashlib.md5((text or "").encode("utf-8")).hexdigest()[:4]


def _clean_url(u) -> str:
    u = str(u or "").strip()
    if not u:
        return ""
    if not (u.startswith("http://") or u.startswith("https://")):
        return ""
    return u.rstrip("/")


def _entry(raw) -> dict:
    """把外部来的条目收敛成固定形状，缺的补空，多的丢掉。"""
    eps = []
    for e in raw.get("endpoints") or []:
        if isinstance(e, dict):
            u = _clean_url(e.get("url"))
            if u:
                eps.append({"url": u, "note": str(e.get("note") or "")})
        else:
            u = _clean_url(e)
            if u:
                eps.append({"url": u, "note": ""})
    try:
        api = int(raw.get("api") or 0)
    except (TypeError, ValueError):
        api = 0
    return {
        "id": str(raw.get("id") or "").strip().lower(),
        "name": str(raw.get("name") or "").strip()[:60],
        "description": str(raw.get("description") or "").strip()[:200],
        "url": _clean_url(raw.get("url")),
        "endpoints": eps,
        "api": api,
        "lang": str(raw.get("lang") or "").strip()[:20],
        "icon": str(raw.get("icon") or "").strip(),
        "tags": [str(t).strip()[:16] for t in (raw.get("tags") or []) if str(t).strip()][:8],
        "open": bool(raw.get("open", True)),
        "contact": str(raw.get("contact") or "").strip()[:120],
        "updated": str(raw.get("updated") or "").strip()[:10],
    }


def validate(data, max_api: int = None):
    """三条规则，顺序固定，先丢脏的再判重复和版本。

    返回 (keep, dropped)，dropped 里带 reason，方便页面上说清为什么没导入。
    """
    max_api = API_VERSION if max_api is None else int(max_api)
    if not isinstance(data, dict):
        return [], [{"id": "", "reason": "bad_format"}]
    keep, dropped, seen = [], [], set()
    for raw in data.get("sites") or []:
        if not isinstance(raw, dict):
            dropped.append({"id": "", "reason": "bad_entry"})
            continue
        it = _entry(raw)
        if not it["url"] and not it["endpoints"]:
            dropped.append({"id": it["id"], "reason": "no_url"})
            continue
        if it["api"] and it["api"] > max_api:
            dropped.append({"id": it["id"], "reason": "api_too_new", "api": it["api"]})
            continue
        if it["id"]:
            if it["id"] in seen:
                dropped.append({"id": it["id"], "reason": "duplicate_id"})
                continue
            seen.add(it["id"])
        keep.append(it)
    return keep, dropped


# ---------------------------------------------------------------- 回访

def _is_private_host(host: str) -> bool:
    """登记接口会去拉对方地址，别让它被拿来探内网。"""
    try:
        infos = socket.getaddrinfo(host, None)
    except Exception:
        return False
    for info in infos:
        try:
            ip = ipaddress.ip_address(info[4][0])
        except ValueError:
            continue
        if ip.is_private or ip.is_loopback or ip.is_link_local or ip.is_reserved:
            return True
    return False


def fetch_meta(url: str):
    """拉一座站的 /meta。先 /api/meta 再 /meta，两个都试不到就返回 None。"""
    url = _clean_url(url)
    if not url:
        return None
    if not config.get("sites", "allow_private", False):
        host = urllib.parse.urlsplit(url).hostname or ""
        if host and _is_private_host(host):
            raise ValueError("地址在内网，登记接口不代拉")
    last = None
    for path in ("/api/meta", "/meta"):
        try:
            req = urllib.request.Request(url + path, headers={"User-Agent": "OpenBBS-registrar"})
            with urllib.request.urlopen(req, timeout=FETCH_TIMEOUT) as resp:
                body = resp.read(FETCH_LIMIT + 1)
            if len(body) > FETCH_LIMIT:
                last = "响应太大"
                continue
            data = json.loads(body.decode("utf-8"))
            if isinstance(data, dict) and "api" in data:
                return data
            last = "不是 /meta 响应"
        except Exception as e:
            last = str(e)
    if last:
        print("回访失败 %s：%s" % (url, last))
    return None


# ---------------------------------------------------------------- 登记

def register(c, payload: dict, max_per_hour: int = 0):
    """登记或更新一座站。

    id 由主站分配：小站自称的 id 没被占就沿用，被占就冲突报错；
    没自称就按站名生成。同一个地址重复登记是幂等的，方便站长改配置再跑。
    """
    url = _clean_url(payload.get("url"))
    if not url:
        raise ValueError("要填站点地址，http:// 或 https:// 开头")

    meta = fetch_meta(url)
    if meta is None:
        raise ValueError("这个地址没有响应 /meta，先在对方站点填好 base_url")

    name = str(payload.get("name") or meta.get("name") or "").strip()[:60]
    if not name:
        raise ValueError("站点没给名字")

    claimed = str(payload.get("site_id") or meta.get("site_id") or "").strip().lower()
    if claimed and not _SITE_ID.match(claimed):
        claimed = ""

    meta_sid = str(meta.get("site_id") or "").strip().lower()
    now = int(time.time())
    row_url = c.execute("SELECT * FROM sites WHERE url=?", (url,)).fetchone()

    def build(sid):
        it = _entry({
            "id": sid,
            "name": name,
            "description": payload.get("description") or meta.get("description") or "",
            "url": url,
            "endpoints": payload.get("endpoints") or meta.get("endpoints") or [],
            "api": meta.get("api") or 0,
            "lang": payload.get("lang") or meta.get("lang") or "zh-Hans",
            "icon": payload.get("icon") or meta.get("icon") or "",
            "tags": payload.get("tags") or meta.get("tags") or [],
            "open": payload.get("open", meta.get("open", True)),
            "contact": payload.get("contact") or meta.get("contact") or "",
            "updated": time.strftime("%Y-%m-%d", time.localtime(now)),
        })
        if not it["endpoints"]:
            it["endpoints"] = [{"url": url, "note": "主入口"}]
        return it

    # 这个地址已经登记过：沿用原 id，更新内容，不再分配。
    if row_url:
        sid = row_url["site_id"]
        if claimed and claimed != sid:
            raise ConflictError("这个地址已经登记为 %s，不能改成 %s" % (sid, claimed))
        it = build(sid)
        _save(c, it, now, verified=True)
        return it, False, meta_sid != sid

    if claimed:
        if c.execute("SELECT 1 FROM sites WHERE site_id=?", (claimed,)).fetchone():
            raise ConflictError("id %s 已被占用，换一个或让对方清空 site_id" % claimed)
        sid = claimed
    else:
        base = slug(name)
        sid = base
        n = 2
        while c.execute("SELECT 1 FROM sites WHERE site_id=?", (sid,)).fetchone():
            sid = "%s-%d" % (base, n)
            n += 1

    it = build(sid)
    _save(c, it, now, verified=True)
    return it, True, meta_sid != sid


def _save(c, it: dict, now: int, verified: bool = False):
    old = c.execute("SELECT created_at FROM sites WHERE site_id=?", (it["id"],)).fetchone()
    c.execute(
        "INSERT INTO sites(site_id, name, description, url, endpoints, api, lang, icon, tags, "
        "open, contact, verified, created_at, updated_at) "
        "VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?) "
        "ON CONFLICT(site_id) DO UPDATE SET name=excluded.name, description=excluded.description, "
        "url=excluded.url, endpoints=excluded.endpoints, api=excluded.api, lang=excluded.lang, "
        "icon=excluded.icon, tags=excluded.tags, open=excluded.open, contact=excluded.contact, "
        "verified=excluded.verified, updated_at=excluded.updated_at",
        (it["id"], it["name"], it["description"], it["url"], json.dumps(it["endpoints"], ensure_ascii=False),
         it["api"], it["lang"], it["icon"], json.dumps(it["tags"], ensure_ascii=False),
         1 if it["open"] else 0, it["contact"], 1 if verified else 0,
         int(old["created_at"]) if old else now, now))
    c.commit()


def row_json(r) -> dict:
    def _load(v, default):
        try:
            return json.loads(v) if v else default
        except Exception:
            return default

    return {
        "id": r["site_id"],
        "name": r["name"],
        "description": r["description"],
        "url": r["url"],
        "endpoints": _load(r["endpoints"], []),
        "api": r["api"],
        "lang": r["lang"],
        "icon": r["icon"],
        "tags": _load(r["tags"], []),
        "open": bool(r["open"]),
        "contact": r["contact"],
        "updated": time.strftime("%Y-%m-%d", time.localtime(r["updated_at"])) if r["updated_at"] else "",
    }


def catalog(c=None) -> dict:
    """主站目录，格式与 /.well-known/bbs.json 一致，可直接给客户端导入。"""
    close = False
    if c is None:
        c = db.conn()
        close = True
    try:
        rows = c.execute("SELECT * FROM sites ORDER BY created_at").fetchall()
        return {
            "schema": SCHEMA,
            "generated": time.strftime("%Y-%m-%dT%H:%M:%S%z", time.localtime()),
            "sites": [row_json(r) for r in rows],
        }
    finally:
        if close:
            c.close()


# ---------------------------------------------------------------- 小站自动登记

_started = False


def start_registrar() -> None:
    """小站：没 site_id、配了主站和 base_url 就自己去登记，拿到 id 存库里。

    后台线程，失败不影响启动；主站不在线就一直慢慢重试。
    """
    global _started
    master = str(config.get("site", "master_url") or "").strip().rstrip("/")
    base = str(config.get("site", "base_url") or "").strip().rstrip("/")
    if not master or not base or site_id() or _started:
        return
    _started = True

    def run():
        # 主站可能比小站起得晚，退避重试：5s、10s、20s… 封顶 5 分钟。
        delay = 5
        while True:
            try:
                req = urllib.request.Request(
                    master + "/api/sites/register",
                    data=json.dumps({"url": base}).encode("utf-8"),
                    headers={"Content-Type": "application/json", "User-Agent": "OpenBBS-self"})
                with urllib.request.urlopen(req, timeout=20) as resp:
                    data = json.loads(resp.read().decode("utf-8"))
                sid = str(data.get("site_id") or "")
                if _SITE_ID.match(sid):
                    c = db.conn()
                    try:
                        c.execute("INSERT INTO sync_state(key, value) VALUES('assigned_site_id', ?) "
                                  "ON CONFLICT(key) DO UPDATE SET value=excluded.value", (sid,))
                        c.commit()
                    finally:
                        c.close()
                    print("已登记为 %s，写进库；站点重启后 /meta 就报这个 id" % sid)
                    return
            except Exception as e:
                print("自动登记没成：%s（%d 秒后再试）" % (e, delay))
            time.sleep(delay)
            delay = min(300, delay * 2)

    threading.Thread(target=run, name="site-registrar", daemon=True).start()
