# -*- coding: utf-8 -*-
"""App 用的 JSON 接口。

数据模型（贴吧式）：
  thread 主题帖      —— threads 表，正文就是「1 楼」
  reply  楼层        —— replies 表，第 1 条 reply 是 2 楼
  楼中楼             —— replies.parent_id 指向被回复的那一层；parent_id=0 表示回复楼主

楼层号不落库，按 id 顺序算，省一层状态。
"""
import base64, hashlib, hmac, json, os, random, re, secrets, shutil, struct, time
from typing import Any, List, Optional

from fastapi import APIRouter, Depends, File, HTTPException, Request, UploadFile
from fastapi.responses import FileResponse
from pydantic import BaseModel

from . import auth, blacklist, config, db, files as filesvc, mailer, sites

router = APIRouter(prefix="/api")

PER_PAGE = config.get("limits", "per_page", 20)
PER_FLOOR_PAGE = config.get("limits", "floor_per_page", 20)



# ---------------------------------------------------------------- 基础


def get_conn():
    c = db.conn()
    try:
        yield c
    finally:
        c.close()


def _token(request: Request):
    h = request.headers.get("authorization", "")
    if h.lower().startswith("bearer "):
        return h[7:].strip()
    return ""


def user_json(row):
    if not row:
        return None
    return {
        "id": row["id"],
        "uid": (row["uid"] if "uid" in row.keys() else None) or row["id"],
        "name": row["name"],
        "nickname": row["nickname"] or row["name"],
        "handle": row["handle"] or "",
        "avatar": row["avatar"] or "",
        "cover": (row["cover"] or "") if "cover" in row.keys() else "",
        "signature": row["signature"] or "",
        "level": min(MAX_LEVEL, row["level"] or 1),
        "is_admin": bool(row["is_admin"]),
        "email": (row["email"] or "") if "email" in row.keys() else "",
    }


USER_COLS = "id, uid, name, nickname, handle, avatar, cover, signature, level, is_admin, email"


HANDLE_RE = re.compile(r"[a-z0-9_]{3,16}")
HANDLE_RESERVED = {
    "admin", "root", "system", "support", "help", "api", "me", "u", "user",
    "settings", "setting", "login", "register", "logout", "search", "img",
    "static", "about", "thread", "threads", "notice",
    "notifications", "null", "undefined", "official",
}


ADMIN_NAME = config.get("admin", "name") or "admin"


def _initial_admin_pw():
    """首个管理员的初始密码。

    配置里没给就随机生成一串，落在 data/admin_initial.txt（600），
    只给部署的人看一眼。默认密码写死在代码里等于没有密码。
    """
    fixed = config.get("admin", "password") or ""
    if fixed:
        return fixed

    f = os.path.join(config.path("data"), "admin_initial.txt")
    if os.path.exists(f):
        try:
            with open(f, "r", encoding="utf-8") as fh:
                got = fh.read().strip()
            if got:
                return got
        except OSError:
            pass

    pw = "".join(secrets.choice("abcdefghjkmnpqrstuvwxyz23456789") for _ in range(12))
    try:
        os.makedirs(os.path.dirname(f), exist_ok=True)
        with open(f, "w", encoding="utf-8") as fh:
            fh.write(pw + "\n")
        os.chmod(f, 0o600)
    except OSError:
        pass
    print("[openbbs] 首次启动，管理员 %s 的初始密码：%s（也写在 %s）"
          % (ADMIN_NAME, pw, f))
    return pw


def ensure_admin():
    """第一个管理员账号：只建一次，之后密码以库里为准。"""
    c = db.conn()
    try:
        row = c.execute("SELECT id, is_admin FROM users WHERE name=?", (ADMIN_NAME,)).fetchone()
        if row is None:
            # 两个进程会同时起来，谁先插入都行，冲突就忽略
            c.execute(
                "INSERT OR IGNORE INTO users(name, pw, created_at, is_admin) VALUES(?,?,?,1)",
                (ADMIN_NAME, auth.hash_pw(_initial_admin_pw()), int(time.time())))
            c.commit()
        elif not row["is_admin"]:
            c.execute("UPDATE users SET is_admin=1 WHERE id=?", (row["id"],))
            c.commit()
    finally:
        c.close()


def _may_delete(user, owner_id):
    if not user:
        return False
    return user["id"] == owner_id or bool(user["is_admin"])


def _load_user(c, uid):
    """token 里的 uid 是「权威用户 id」：主站就是本机 id，小站是主站的 id。

    小站先按 master_uid 找影子行。**找不到就不再退回本地 id** ——
    否则主站的 uid=2 会直接认成本站 id=2 的另一个人，等于越权。
    主站没有 master_uid 这一层，按 id 走。
    """
    if not uid:
        return None
    row = c.execute("SELECT %s FROM users WHERE master_uid=?" % USER_COLS, (uid,)).fetchone()
    if row is not None:
        return row
    if config.get("site", "master_url"):
        return _ensure_shadow(c, uid)
    return c.execute("SELECT %s FROM users WHERE id=?" % USER_COLS, (uid,)).fetchone()


def _ensure_shadow(c, muid):
    """小站第一次见到某个主站账号：建一条影子行，只认 master_uid。

    资料（昵称、头像）之后按主站地址取，这里先占个名，别让页面空着。
    """
    base = "u%d" % int(muid)
    name = base
    for i in range(1, 200):
        if not c.execute("SELECT 1 FROM users WHERE name=?", (name,)).fetchone():
            break
        name = "%s_%d" % (base, i)
    else:
        return None
    try:
        c.execute("INSERT INTO users(name, pw, created_at, master_uid, nickname) "
                  "VALUES(?,?,?,?,?)",
                  (name, "", int(time.time()), int(muid), base))
        c.commit()
    except Exception:
        c.rollback()
    return c.execute("SELECT %s FROM users WHERE master_uid=?" % USER_COLS, (int(muid),)).fetchone()


def optional_user(request: Request, c=Depends(get_conn)):
    uid = auth.read_token(_token(request))
    # 读接口也拦：封号之后这个账号什么都看不到。
    if blacklist.is_banned(c, uid):
        raise HTTPException(403, blacklist.BANNED_MSG)
    return _load_user(c, uid)


def require_user(request: Request, c=Depends(get_conn)):
    uid = auth.read_token(_token(request))
    if blacklist.is_banned(c, uid):
        raise HTTPException(403, blacklist.BANNED_MSG)
    u = _load_user(c, uid)
    if not u:
        raise HTTPException(401, "请先登录")
    return u


MAX_LEVEL = config.get("limits", "max_level", 99)  # 等级上限


def _level_of(c, uid):
    """等级：发帖 + 回帖数换算，聊胜于无。"""
    n = c.execute(
        "SELECT (SELECT COUNT(*) FROM threads WHERE user_id=?) + "
        "(SELECT COUNT(*) FROM replies WHERE user_id=?) AS n", (uid, uid)).fetchone()["n"]
    return min(MAX_LEVEL, max(1, int(n ** 0.5) + 1))


def _refresh_level(c, uid):
    """按活跃度重算等级，但只升不降，免得手调过的等级被冲掉。"""
    cur = c.execute("SELECT level FROM users WHERE id=?", (uid,)).fetchone()
    keep = (cur["level"] if cur else 0) or 1
    lv = min(MAX_LEVEL, max(keep, _level_of(c, uid)))
    c.execute("UPDATE users SET level=? WHERE id=?", (lv, uid))


# ---------------------------------------------------------------- 入参


class Credentials(BaseModel):
    name: str
    password: str


class EmailAsk(BaseModel):
    email: str = ""


class RegisterIn(BaseModel):
    name: str
    password: str
    email: str = ""
    code: str = ""


class ResetIn(BaseModel):
    email: str = ""
    code: str = ""
    password: str = ""


class NewThread(BaseModel):
    title: str
    body: str
    images: Optional[list] = None
    files: Optional[list] = None


class NewReply(BaseModel):
    body: str
    parent_id: Optional[int] = None
    images: Optional[list] = None
    files: Optional[list] = None


class PatchThread(BaseModel):
    title: Optional[str] = None
    body: Optional[str] = None
    images: Optional[List[str]] = None
    files: Optional[list] = None


class PatchReply(BaseModel):
    body: Optional[str] = None
    images: Optional[List[str]] = None
    files: Optional[list] = None


class NewImage(BaseModel):
    name: str = ""
    data: str


UPLOAD_DIR = config.path("uploads")
MAX_IMAGE = config.get("limits", "max_image_mb", 5) * 1024 * 1024
MAX_ANIM = config.get("limits", "max_anim_mb", 10) * 1024 * 1024  # 客户端已经压过，超过就是没压
MAX_IMAGES = config.get("limits", "max_images", 9)

NAME_MIN = config.get("limits", "username_min", 2)
NAME_MAX = config.get("limits", "username_max", 20)
PW_MIN = config.get("limits", "password_min", 8)
TITLE_MAX = config.get("limits", "title_max", 120)
BODY_MAX = config.get("limits", "body_max", 20000)


def _norm_imgs(v):
    """只认本机 /img/ 开头的路径，别的一律丢掉。"""
    out = []
    for x in (v or []):
        if isinstance(x, str) and x.startswith("/img/") and ".." not in x:
            out.append(x)
        if len(out) >= MAX_IMAGES:
            break
    return out


def _load_imgs(raw):
    try:
        return _norm_imgs(json.loads(raw or "[]"))
    except Exception:
        return []


def _save_imgs(v):
    return json.dumps(_norm_imgs(v), ensure_ascii=False)


# ---------------------------------------------------------------- 附件


_F_URL = re.compile(r"^(?:/f/)?([0-9a-f]{20})$")


def _load_files(raw):
    try:
        v = json.loads(raw or "[]")
    except Exception:
        return []
    return [x for x in v if isinstance(x, dict) and x.get("url")]


def _save_files(v):
    return json.dumps(v or [], ensure_ascii=False)


def _files_payload(raw):
    return {"files": _load_files(raw)}


def _norm_files(v, c, user, cap=0):
    """客户端只报地址，名字和大小一律从库里取——别信客户端报的数。

    只认自己传的文件（管理员例外），一帖最多 cap 个。
    """
    cap = cap or filesvc.MAX_FILES
    out, seen = [], set()
    for item in (v or [])[:cap]:
        raw = item.get("url") if isinstance(item, dict) else item
        m = _F_URL.match(str(raw or "").strip())
        if not m or m.group(1) in seen:
            continue
        d = m.group(1)
        row = c.execute("SELECT digest, name, size, uploader FROM files WHERE digest=?",
                        (d,)).fetchone()
        if not row:
            continue
        if row["uploader"] != user["id"] and not user["is_admin"]:
            continue
        seen.add(d)
        out.append({"url": "/f/" + d, "name": row["name"], "size": row["size"]})
    return out


def _read_size(path):
    """从文件头读宽高，不解码整张图。四种格式都认这个服务端能收的。

    返回 (w, h)，认不出来返回 None。
    """
    with open(path, "rb") as f:
        head = f.read(32)
        if head[:8] == b"\x89PNG\r\n\x1a\n":
            return struct.unpack(">II", head[16:24])
        if head[:6] in (b"GIF87a", b"GIF89a"):
            return struct.unpack("<HH", head[6:10])
        if head[:4] == b"RIFF" and head[8:12] == b"WEBP":
            kind = head[12:16]
            if kind == b"VP8X":
                return (int.from_bytes(head[24:27], "little") + 1,
                        int.from_bytes(head[27:30], "little") + 1)
            if kind == b"VP8L":
                b = struct.unpack("<I", head[21:25])[0]
                return (b & 0x3FFF) + 1, ((b >> 14) & 0x3FFF) + 1
            if kind == b"VP8 ":
                return (struct.unpack("<H", head[26:28])[0] & 0x3FFF,
                        struct.unpack("<H", head[28:30])[0] & 0x3FFF)
            return None
        if head[:3] != b"\xff\xd8\xff":
            return None
        # JPEG：一路跳到 SOF 段，那里面才是真实宽高。
        f.seek(2)
        while True:
            b = f.read(1)
            while b and b != b"\xff":
                b = f.read(1)
            if not b:
                return None
            m = f.read(1)
            while m == b"\xff":
                m = f.read(1)
            if not m:
                return None
            code = m[0]
            if code == 0xD8 or code == 0x01 or 0xD0 <= code <= 0xD7:
                continue
            ln = struct.unpack(">H", f.read(2))[0]
            if code in (0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6,
                        0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF):
                f.read(1)
                h, w = struct.unpack(">HH", f.read(4))
                return w, h
            f.seek(ln - 2, 1)


def _exif_turn(path):
    """EXIF 里的旋转标记。手机上竖着拍的照片像素是横的，5-8 要换宽高。"""
    try:
        with open(path, "rb") as f:
            data = f.read(65536)
        i = data.find(b"Exif\x00\x00")
        if i < 0:
            return 1
        t = data[i + 6:]
        if len(t) < 8:
            return 1
        end = "<" if t[:2] == b"II" else ">"
        off = struct.unpack(end + "I", t[4:8])[0]
        n = struct.unpack(end + "H", t[off:off + 2])[0]
        for k in range(n):
            e = off + 2 + k * 12
            tag = struct.unpack(end + "H", t[e:e + 2])[0]
            if tag == 0x0112:
                v = struct.unpack(end + "H", t[e + 8:e + 10])[0]
                return v if 1 <= v <= 8 else 1
    except Exception:
        pass
    return 1


_IMG_SIZE = {}
_IMG_SIZE_MAX = 5000


def _img_size(url):
    """帖子列表一屏十几张图，尺寸读一次就记着，别每次翻文件。"""
    if url in _IMG_SIZE:
        return _IMG_SIZE[url]
    out = None
    try:
        if isinstance(url, str) and url.startswith("/img/"):
            path = os.path.join(UPLOAD_DIR, url[5:])
            if os.path.isfile(path):
                wh = _read_size(path)
                if wh and wh[0] > 0 and wh[1] > 0:
                    w, h = wh
                    if _exif_turn(path) in (5, 6, 7, 8):
                        w, h = h, w
                    out = [w, h]
    except Exception:
        out = None
    if len(_IMG_SIZE) > _IMG_SIZE_MAX:
        _IMG_SIZE.clear()
    _IMG_SIZE[url] = out
    return out


def _imgs_payload(raw):
    """images 和它们的宽高一起给出去，客户端才能提前把位置留准。"""
    imgs = _load_imgs(raw)
    return {"images": imgs, "img_sizes": [_img_size(u) for u in imgs]}



_HTML_TAG_RE = re.compile(r"<!--.*?-->|</?[A-Za-z][A-Za-z0-9-]*(?:\s[^<>]*)?/?>", re.S)
_HTML_ENT = {"&lt;": "<", "&gt;": ">", "&amp;": "&", "&quot;": '"', "&#39;": "'", "&nbsp;": " "}


def _excerpt(body, n=240):
    """列表页用的正文预览：剥掉 HTML 标签、还原常见实体，压掉空白再截到 n 字。"""
    text = _HTML_TAG_RE.sub("", body or "")
    for k, v in _HTML_ENT.items():
        text = text.replace(k, v)
    text = re.sub(r"\s+", " ", text).strip()
    return text[:n]


# ---------------------------------------------------------------- @ 提醒

MENTION_RE = re.compile(r"@([A-Za-z0-9_]{1,32})")


def _notify(c, user_id, actor_id, kind, tid, rid, body, now):
    c.execute(
        "INSERT INTO notifications(user_id, actor_id, kind, thread_id, reply_id, body, created_at) "
        "VALUES(?,?,?,?,?,?,?)",
        (user_id, actor_id, kind, tid, rid, (body or "")[:120], now))


def _mention_ids(c, body, skip):
    """正文里 @ 到的人。skip 里的跳过，免得同一次动作通知两遍。

    只认 handle 和 name（英文数字下划线），昵称里有空格没法当 @ 用。
    """
    cand = {m.lower() for m in MENTION_RE.findall(body or "")}
    if not cand:
        return []
    rows = c.execute("SELECT id, name, handle FROM users").fetchall()
    out = []
    for r in rows:
        keys = {(r["handle"] or "").lower(), (r["name"] or "").lower()}
        if keys & cand and r["id"] not in skip and r["id"] not in out:
            out.append(r["id"])
    return out


def _notify_mentions(c, body, actor_id, tid, rid, now, skip=()):
    for uid in _mention_ids(c, body, set(skip) | {actor_id}):
        _notify(c, uid, actor_id, "mention", tid, rid, body, now)


# ---------------------------------------------------------------- 账号


# 邮箱注册：先发 6 位验证码，验证过了才建号。
# 老用户 email 为空，登录照旧，不补不拦。
EMAIL_RE = re.compile(r"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$")
CODE_TTL = config.get("auth", "code_ttl", 600)
CODE_MAX_TRIES = config.get("auth", "code_max_tries", 5)
SEND_COOLDOWN = config.get("auth", "send_cooldown", 60)          # 同一邮箱两次发码间隔
SEND_PER_HOUR_EMAIL = config.get("auth", "send_per_hour_email", 3)
SEND_PER_HOUR_IP = config.get("auth", "send_per_hour_ip", 5)
REG_PER_HOUR_IP = config.get("auth", "reg_per_hour_ip", 5)
LOGIN_FAIL_MAX = config.get("auth", "login_fail_max", 5)          # 同一 IP 每分钟密码错几次就拦
LOGIN_FAIL_WINDOW = config.get("auth", "login_fail_window", 60)
REGISTER_OPEN = bool(config.get("auth", "register_open", True))
REQUIRE_EMAIL = bool(config.get("auth", "require_email", True))
_LOGIN_FAIL = {}


def _ip(request: Request) -> str:
    xff = request.headers.get("x-forwarded-for", "")
    if xff:
        return xff.split(",")[0].strip()
    return request.client.host if request.client else ""


def _code_hash(email: str, code: str) -> str:
    return auth.hmac_hex(("%s|%s" % (email, code)).encode())


def _norm_email(raw: str) -> str:
    e = (raw or "").strip().lower()
    if len(e) > 120 or not EMAIL_RE.match(e):
        raise HTTPException(400, "邮箱格式不对")
    return e


@router.post("/register/code")
def register_code(p: EmailAsk, request: Request, c=Depends(get_conn)):
    if not REGISTER_OPEN:
        raise HTTPException(403, "本站暂不开放注册")
    email = _norm_email(p.email)
    ip = _ip(request)
    now = int(time.time())

    row = c.execute("SELECT sent_at FROM email_codes WHERE email=?", (email,)).fetchone()
    if row and now - row["sent_at"] < SEND_COOLDOWN:
        wait = SEND_COOLDOWN - (now - row["sent_at"])
        raise HTTPException(429, "刚发过，%d 秒后再试" % wait)

    if c.execute("SELECT 1 FROM users WHERE lower(email)=?", (email,)).fetchone():
        raise HTTPException(409, "这个邮箱已经注册过了")

    c.execute("DELETE FROM email_sends WHERE created_at < ?", (now - 86400,))
    if c.execute("SELECT COUNT(*) FROM email_sends WHERE email=? AND created_at>?",
                 (email, now - 3600)).fetchone()[0] >= SEND_PER_HOUR_EMAIL:
        raise HTTPException(429, "这个邮箱今天发太多次了，过一会儿再试")
    if ip and c.execute("SELECT COUNT(*) FROM email_sends WHERE ip=? AND created_at>?",
                        (ip, now - 3600)).fetchone()[0] >= SEND_PER_HOUR_IP:
        raise HTTPException(429, "发得太频繁了，过一会儿再试")

    code = "%06d" % (int.from_bytes(os.urandom(4), "big") % 1000000)
    c.execute("""INSERT INTO email_codes(email, code_hash, expires_at, sent_at, ip, tries)
                 VALUES(?,?,?,?,?,0)
                 ON CONFLICT(email) DO UPDATE SET
                   code_hash=excluded.code_hash, expires_at=excluded.expires_at,
                   sent_at=excluded.sent_at, ip=excluded.ip, tries=0""",
              (email, _code_hash(email, code), now + CODE_TTL, now, ip))
    c.execute("INSERT INTO email_sends(email, ip, created_at) VALUES(?,?,?)", (email, ip, now))
    c.commit()

    try:
        mailer.send_code(email, code, CODE_TTL // 60, kind="register")
    except mailer.MailNotConfigured:
        raise HTTPException(503, "邮件服务没配好，注册暂时关着")
    except mailer.MailSendError:
        raise HTTPException(502, "验证码没发出去，稍后再试")

    return {"ok": True, "cooldown": SEND_COOLDOWN}


@router.post("/register")
def register(p: RegisterIn, request: Request, c=Depends(get_conn)):
    if not REGISTER_OPEN:
        raise HTTPException(403, "本站暂不开放注册")
    name = p.name.strip()
    if not (NAME_MIN <= len(name) <= NAME_MAX):
        raise HTTPException(400, "用户名 %d–%d 个字符" % (NAME_MIN, NAME_MAX))
    if len(p.password) < PW_MIN:
        raise HTTPException(400, "密码至少 %d 位" % PW_MIN)
    if not p.email or not p.code:
        raise HTTPException(400, "注册要用邮箱，先收验证码")
    email = _norm_email(p.email)
    ip = _ip(request)
    now = int(time.time())

    if ip and c.execute("SELECT COUNT(*) FROM users WHERE reg_ip=? AND created_at>?",
                        (ip, now - 3600)).fetchone()[0] >= REG_PER_HOUR_IP:
        raise HTTPException(429, "注册太频繁了，过一会儿再试")

    row = c.execute("SELECT * FROM email_codes WHERE email=?", (email,)).fetchone()
    if not row:
        raise HTTPException(400, "先点「获取验证码」")
    if row["expires_at"] < now:
        c.execute("DELETE FROM email_codes WHERE email=?", (email,))
        c.commit()
        raise HTTPException(400, "验证码过期了，重新发一个")
    if row["tries"] >= CODE_MAX_TRIES:
        raise HTTPException(429, "验证码错太多次，重新发一个")

    if not hmac.compare_digest(row["code_hash"], _code_hash(email, p.code.strip())):
        c.execute("UPDATE email_codes SET tries=tries+1 WHERE email=?", (email,))
        c.commit()
        raise HTTPException(400, "验证码不对")

    if c.execute("SELECT 1 FROM users WHERE lower(email)=?", (email,)).fetchone():
        raise HTTPException(409, "这个邮箱已经注册过了")
    if c.execute("SELECT 1 FROM users WHERE name=?", (name,)).fetchone():
        raise HTTPException(409, "这个名字有人用了")

    c.execute("DELETE FROM email_codes WHERE email=?", (email,))
    next_uid = c.execute("SELECT COALESCE(MAX(uid),0)+1 FROM users").fetchone()[0]
    cur = c.execute(
        "INSERT INTO users(name, pw, created_at, uid, email, email_verified, reg_ip) VALUES(?,?,?,?,?,1,?)",
        (name, auth.hash_pw(p.password), now, next_uid, email, ip))
    c.commit()
    uid = cur.lastrowid
    c.execute("UPDATE users SET handle=? WHERE id=?",
              (db.unique_handle(c, name, uid), uid))
    c.commit()
    return {"token": auth.make_token(uid), "user": user_json(_load_user(c, uid))}


# 找回密码：发码 → 校验 → 改密码。
# 用途前缀塞进 email_codes.email，避免和注册码互相覆盖。
# 邮箱不存在也返回 ok，不给枚举账号的口子。
def _send_code(c, key, email, ip, now, kind="reset"):
    code = "%06d" % (int.from_bytes(os.urandom(4), "big") % 1000000)
    c.execute("""INSERT INTO email_codes(email, code_hash, expires_at, sent_at, ip, tries)
                 VALUES(?,?,?,?,?,0)
                 ON CONFLICT(email) DO UPDATE SET
                   code_hash=excluded.code_hash, expires_at=excluded.expires_at,
                   sent_at=excluded.sent_at, ip=excluded.ip, tries=0""",
              (key, _code_hash(key, code), now + CODE_TTL, now, ip))
    c.execute("INSERT INTO email_sends(email, ip, created_at) VALUES(?,?,?)", (email, ip, now))
    c.commit()
    mailer.send_code(email, code, CODE_TTL // 60, kind=kind)


@router.post("/password/code")
def password_code(p: EmailAsk, request: Request, c=Depends(get_conn)):
    email = _norm_email(p.email)
    ip = _ip(request)
    now = int(time.time())
    key = "rst:" + email

    row = c.execute("SELECT sent_at FROM email_codes WHERE email=?", (key,)).fetchone()
    if row and now - row["sent_at"] < SEND_COOLDOWN:
        raise HTTPException(429, "刚发过，%d 秒后再试" % (SEND_COOLDOWN - (now - row["sent_at"])))

    c.execute("DELETE FROM email_sends WHERE created_at < ?", (now - 86400,))
    if c.execute("SELECT COUNT(*) FROM email_sends WHERE email=? AND created_at>?",
                 (email, now - 3600)).fetchone()[0] >= SEND_PER_HOUR_EMAIL:
        raise HTTPException(429, "这个邮箱今天发太多次了，过一会儿再试")
    if ip and c.execute("SELECT COUNT(*) FROM email_sends WHERE ip=? AND created_at>?",
                        (ip, now - 3600)).fetchone()[0] >= SEND_PER_HOUR_IP:
        raise HTTPException(429, "发得太频繁了，过一会儿再试")

    if c.execute("SELECT 1 FROM users WHERE lower(email)=?", (email,)).fetchone():
        try:
            _send_code(c, key, email, ip, now, kind="reset")
        except mailer.MailNotConfigured:
            raise HTTPException(503, "邮件服务没配好，暂时发不出")
        except mailer.MailSendError:
            raise HTTPException(502, "验证码没发出去，稍后再试")
    return {"ok": True, "cooldown": SEND_COOLDOWN}


@router.post("/password/reset")
def password_reset(p: ResetIn, c=Depends(get_conn)):
    if len(p.password) < PW_MIN:
        raise HTTPException(400, "密码至少 %d 位" % PW_MIN)
    if not p.email or not p.code:
        raise HTTPException(400, "要填邮箱和验证码")
    email = _norm_email(p.email)
    key = "rst:" + email
    now = int(time.time())

    row = c.execute("SELECT * FROM email_codes WHERE email=?", (key,)).fetchone()
    if not row:
        raise HTTPException(400, "先点「发送验证码」")
    if row["expires_at"] < now:
        c.execute("DELETE FROM email_codes WHERE email=?", (key,))
        c.commit()
        raise HTTPException(400, "验证码过期了，重新发一个")
    if row["tries"] >= CODE_MAX_TRIES:
        raise HTTPException(429, "验证码错太多次，重新发一个")
    if not hmac.compare_digest(row["code_hash"], _code_hash(key, p.code.strip())):
        c.execute("UPDATE email_codes SET tries=tries+1 WHERE email=?", (key,))
        c.commit()
        raise HTTPException(400, "验证码不对")

    user = c.execute("SELECT * FROM users WHERE lower(email)=?", (email,)).fetchone()
    if not user:
        raise HTTPException(400, "这个邮箱没绑账号")

    c.execute("DELETE FROM email_codes WHERE email=?", (key,))
    c.execute("UPDATE users SET pw=? WHERE id=?", (auth.hash_pw(p.password), user["id"]))
    c.commit()
    return {"token": auth.make_token(user["id"]), "user": user_json(_load_user(c, user["id"]))}


# ---------------------------------------------------------------- 账号安全


class BindEmailIn(BaseModel):
    email: str = ""
    code: str = ""


@router.post("/account/email/code")
def account_email_code(p: EmailAsk, request: Request,
                       user=Depends(require_user), c=Depends(get_conn)):
    """给当前登录的账号绑邮箱（或换绑）。

    早一批账号注册时还没有邮箱，将来忘了密码就彻底找不回来。这条是给它们补的路。
    """
    email = _norm_email(p.email)
    ip = _ip(request)
    now = int(time.time())
    key = "bind:%d:%s" % (user["id"], email)

    other = c.execute("SELECT id FROM users WHERE lower(email)=? AND id<>?",
                      (email, user["id"])).fetchone()
    if other:
        raise HTTPException(409, "这个邮箱已经绑了别的账号")

    row = c.execute("SELECT sent_at FROM email_codes WHERE email=?", (key,)).fetchone()
    if row and now - row["sent_at"] < SEND_COOLDOWN:
        raise HTTPException(429, "刚发过，%d 秒后再试" % (SEND_COOLDOWN - (now - row["sent_at"])))

    c.execute("DELETE FROM email_sends WHERE created_at < ?", (now - 86400,))
    if c.execute("SELECT COUNT(*) FROM email_sends WHERE email=? AND created_at>?",
                 (email, now - 3600)).fetchone()[0] >= SEND_PER_HOUR_EMAIL:
        raise HTTPException(429, "这个邮箱今天发太多次了，过一会儿再试")
    if ip and c.execute("SELECT COUNT(*) FROM email_sends WHERE ip=? AND created_at>?",
                        (ip, now - 3600)).fetchone()[0] >= SEND_PER_HOUR_IP:
        raise HTTPException(429, "发得太频繁了，过一会儿再试")

    try:
        _send_code(c, key, email, ip, now, kind="bind")
    except mailer.MailNotConfigured:
        raise HTTPException(503, "邮件服务没配好，暂时发不出")
    except mailer.MailSendError:
        raise HTTPException(502, "验证码没发出去，稍后再试")
    return {"ok": True, "cooldown": SEND_COOLDOWN}


@router.post("/account/email/bind")
def account_email_bind(p: BindEmailIn, user=Depends(require_user), c=Depends(get_conn)):
    if not p.email or not p.code:
        raise HTTPException(400, "要填邮箱和验证码")
    email = _norm_email(p.email)
    key = "bind:%d:%s" % (user["id"], email)
    now = int(time.time())

    row = c.execute("SELECT * FROM email_codes WHERE email=?", (key,)).fetchone()
    if not row:
        raise HTTPException(400, "先点「发送验证码」")
    if row["expires_at"] < now:
        c.execute("DELETE FROM email_codes WHERE email=?", (key,))
        c.commit()
        raise HTTPException(400, "验证码过期了，重新发一个")
    if row["tries"] >= CODE_MAX_TRIES:
        raise HTTPException(429, "验证码错太多次，重新发一个")
    if not hmac.compare_digest(row["code_hash"], _code_hash(key, p.code.strip())):
        c.execute("UPDATE email_codes SET tries=tries+1 WHERE email=?", (key,))
        c.commit()
        raise HTTPException(400, "验证码不对")

    other = c.execute("SELECT id FROM users WHERE lower(email)=? AND id<>?",
                      (email, user["id"])).fetchone()
    if other:
        raise HTTPException(409, "这个邮箱已经绑了别的账号")

    c.execute("DELETE FROM email_codes WHERE email=?", (key,))
    c.execute("UPDATE users SET email=?, email_verified=1 WHERE id=?", (email, user["id"]))
    c.commit()
    return {"user": user_json(_load_user(c, user["id"]))}


# ---------------------------------------------------------------- 管理员：重置密码
# 没邮箱、也没旧设备留着登录凭证的账号，最后就靠这条路。

_PW_ALPHABET = "abcdefghjkmnpqrstuvwxyz23456789"


def _temp_password(n=10):
    """临时密码：去掉容易看错的 l、0、1、I、O，念得出来、抄得对。"""
    raw = os.urandom(n)
    return "".join(_PW_ALPHABET[b % len(_PW_ALPHABET)] for b in raw)


def _need_admin(user):
    if not user or not user["is_admin"]:
        raise HTTPException(403, "只有管理员能做这个")


@router.get("/admin/users")
def admin_users(q: str = "", user=Depends(optional_user), c=Depends(get_conn)):
    _need_admin(user)
    like = "%" + (q or "").strip() + "%"
    rows = c.execute("""
        SELECT id, name, nickname, email, created_at, is_admin
        FROM users WHERE name LIKE ? OR nickname LIKE ? OR uid LIKE ?
        ORDER BY id DESC LIMIT 200
    """, (like, like, like)).fetchall()
    return {"items": [{
        "id": r["id"],
        "name": r["name"],
        "nickname": r["nickname"] or r["name"],
        "email": r["email"] or "",
        "created_at": r["created_at"],
        "is_admin": bool(r["is_admin"]),
    } for r in rows]}


@router.post("/admin/user/{uid}/reset_pw")
def admin_reset_pw(uid: int, user=Depends(optional_user), c=Depends(get_conn)):
    _need_admin(user)
    row = c.execute("SELECT id, name, nickname FROM users WHERE id=?", (uid,)).fetchone()
    if not row:
        raise HTTPException(404, "没这个账号")
    tmp = _temp_password()
    c.execute("UPDATE users SET pw=? WHERE id=?", (auth.hash_pw(tmp), uid))
    c.commit()
    return {
        "name": row["name"],
        "nickname": row["nickname"] or row["name"],
        "password": tmp,
    }


@router.post("/login")
def login(p: Credentials, request: Request, c=Depends(get_conn)):
    ip = _ip(request)
    now = int(time.time())
    if ip:
        hits = [t for t in _LOGIN_FAIL.get(ip, ()) if now - t < LOGIN_FAIL_WINDOW]
        _LOGIN_FAIL[ip] = hits
        if len(hits) >= LOGIN_FAIL_MAX:
            raise HTTPException(429, "密码错太多次，%d 秒后再试"
                                % (LOGIN_FAIL_WINDOW - (now - hits[0])))
    row = c.execute("SELECT * FROM users WHERE name=?", (p.name.strip(),)).fetchone()
    if not row or not auth.check_pw(p.password, row["pw"]):
        if ip:
            _LOGIN_FAIL.setdefault(ip, []).append(now)
        raise HTTPException(401, "用户名或密码不对")
    # 封号之后连登录这一步都不给过，别让人拿着新 token 到处试。
    if blacklist.is_banned(c, row["id"]):
        raise HTTPException(403, blacklist.BANNED_MSG)
    if ip:
        _LOGIN_FAIL.pop(ip, None)
    return {"token": auth.make_token(row["id"]), "user": user_json(_load_user(c, row["id"]))}


@router.get("/me")
def me(user=Depends(optional_user)):
    return {"user": user_json(user)}


# ---------------------------------------------------------------- 发帖


@router.post("/threads")
def create_thread(p: NewThread, c=Depends(get_conn), user=Depends(require_user)):
    title, body = p.title.strip()[:TITLE_MAX], p.body.strip()[:BODY_MAX]
    attach = _norm_files(p.files, c, user)
    if not title or (not body and not p.images and not attach):
        raise HTTPException(400, "标题要填，正文、图片、附件至少一样")
    now = int(time.time())
    cur = c.execute(
        "INSERT INTO threads(title, body, user_id, created_at, updated_at, reply_count, images, files) "
        "VALUES(?,?,?,?,?,0,?,?)",
        (title, body, user["id"], now, now, _save_imgs(p.images), _save_files(attach)))
    tid = cur.lastrowid
    _notify_mentions(c, body, user["id"], tid, None, now)
    _refresh_level(c, user["id"])
    c.commit()
    return {"thread_id": tid}


# ---------------------------------------------------------------- 主题帖


APK_ROOT = config.path("apk")
# stable 给所有人，beta 只给管理员。旧包全在 stable 里。
APK_DIRS = {
    "stable": os.path.join(APK_ROOT, "stable"),
    "beta": os.path.join(APK_ROOT, "beta"),
}
APK_RE = re.compile(r"app-(\d+)\.(\d+)\.(\d+)\+(\d+)\.apk$")


def _latest_notes(text: str) -> str:
    """notes.txt 是从早期一路攒下来的，只留最后一版。

    手表这种小屏，整段塞进弹窗会把按钮顶出屏幕。
    """
    lines = text.splitlines()
    start = 0
    for i, line in enumerate(lines):
        if re.match(r"^\s*\d+\.\d+\.\d+\+\d+\s*$", line):
            start = i
    return "\n".join(lines[start:]).strip()


def _latest_apk(channel: str = "stable"):
    """某个通道里 build 号最大的那个，文件名就是版本。"""
    best = None
    try:
        names = os.listdir(APK_DIRS[channel])
    except FileNotFoundError:
        names = []
    for name in names:
        m = APK_RE.match(name)
        if not m:
            continue
        v = (int(m.group(1)), int(m.group(2)), int(m.group(3)), int(m.group(4)))
        if best is None or v[3] > best[0][3]:
            best = (v, name)
    return best


@router.get("/app/latest")
def app_latest(channel: str = "", user=Depends(optional_user)):
    # 站长可以整体关掉更新检查；关掉后自动检查静默跳过，手动检查会看到这句话。
    if not config.get("update", "enabled", True):
        raise HTTPException(404, "本站没有开启更新检查")
    # 内测通道只对管理员开：普通用户传了 channel 也按稳定版走。
    want = "beta" if (user and user["is_admin"] and channel.lower() != "stable") else "stable"
    best = _latest_apk(want)
    if best is None and want != "stable":
        # 内测目录还空着（或者刚清空），退回稳定版，别让人卡在 404。
        want, best = "stable", _latest_apk("stable")
    if not best:
        raise HTTPException(404, "服务器上还没有安装包")
    v, name = best
    path = os.path.join(APK_DIRS[want], name)
    notes = ""
    nf = os.path.join(APK_DIRS[want], "notes.txt")
    if os.path.exists(nf):
        with open(nf, encoding="utf-8") as f:
            notes = _latest_notes(f.read())
    return {
        "version": f"{v[0]}.{v[1]}.{v[2]}",
        "build": v[3],
        "size": os.path.getsize(path),
        "url": f"/apk/{want}/{name}",
        "channel": want,
        "notes": notes,
        # 下面几项是弹窗策略，客户端拿去决定什么时候弹、能不能跳过。
        "force_below": config.get("update", "force_below", 0) or 0,
        "check_hours": config.get("update", "check_hours", 24),
        "remind_hours": config.get("update", "remind_hours", 24),
        "title": config.get("update", "title", "") or "",
        "message": config.get("update", "message", "") or "",
    }


@router.get("/feed")
def feed(page: int = 1, sort: str = "created", c=Depends(get_conn), user=Depends(optional_user)):
    page = max(1, page)
    order = "t.created_at DESC" if sort == "created" else "t.updated_at DESC"
    rows = c.execute(
        "SELECT t.id, t.title, t.body, t.created_at, t.updated_at, t.edited_at, t.reply_count, t.view_count, "
        "t.is_good, t.is_top, t.images, t.files, t.user_id, u.name AS author, u.nickname AS author_nick, u.handle AS author_handle "
        "FROM threads t JOIN users u ON u.id=t.user_id "
        "ORDER BY t.is_top DESC, "
        "(CASE WHEN t.is_top=1 THEN t.created_at ELSE 0 END) ASC, " + order + " LIMIT ? OFFSET ?",
        (PER_PAGE, (page - 1) * PER_PAGE)).fetchall()
    return {"items": [{
        "id": r["id"],
        "title": r["title"],
        "excerpt": _excerpt(r["body"] if "body" in r.keys() else ""),
        "author": r["author_nick"] or r["author"],
        "handle": r["author_handle"] or "",
        "reply_count": r["reply_count"],
        "view_count": r["view_count"],
        "is_good": bool(r["is_good"]),
        "is_top": bool(r["is_top"]) if "is_top" in r.keys() else False,
        "can_delete": _may_delete(user, r["user_id"]),
        "updated_at": r["updated_at"],
        "edited_at": r["edited_at"] or 0,
        **_imgs_payload(r["images"] if "images" in r.keys() else None),
        **_files_payload(r["files"] if "files" in r.keys() else None),
    } for r in rows], "page": page}


def _reply_json(row):
    return {
        "id": row["id"],
        "body": row["body"],
        "author": row["author_nick"] or row["author"],
        "handle": row["author_handle"] or "",
        "author_name": row["author"] or "",
        "author_avatar": row["author_avatar"] or "",
        "author_id": row["user_id"],
        "level": row["level"] or 1,
        "signature": row["signature"] or "",
        "created_at": row["created_at"],
        "agree_count": row["agree_count"],
        "edited_at": (row["edited_at"] or 0) if "edited_at" in row.keys() else 0,
        **_imgs_payload(row["images"]),
        **_files_payload(row["files"]),
        "subs": [],
    }


@router.get("/t/{tid}")
def thread_detail(tid: int, page: int = 1, post: int = 0, floor: int = 0, c=Depends(get_conn), user=Depends(optional_user)):
    t = c.execute(
        "SELECT t.*, u.name AS author, u.nickname AS author_nick, u.handle AS author_handle, u.signature, u.level, "
        "u.name AS author_name, u.avatar AS author_avatar "
        "FROM threads t JOIN users u ON u.id=t.user_id "
        " WHERE t.id=?", (tid,)).fetchone()
    if not t:
        raise HTTPException(404, "帖子不存在")
    c.execute("UPDATE threads SET view_count=view_count+1 WHERE id=?", (tid,))
    if user:
        c.execute(
            "INSERT INTO history(user_id, thread_id, viewed_at) VALUES(?,?,?) "
            "ON CONFLICT(user_id, thread_id) DO UPDATE SET viewed_at=excluded.viewed_at",
            (user["id"], tid, int(time.time())))
    c.commit()

    page = max(1, page)
    total_replies = t["reply_count"]
    total_floors = total_replies + 1
    pages = max(1, -(-total_floors // PER_FLOOR_PAGE))

    # post>0 时告诉客户端这条回复在第几页，客户端据此定位
    focus_page = 0
    if post > 0:
        fr = c.execute(
            "SELECT (SELECT COUNT(*) FROM replies r2 "
            "        WHERE r2.thread_id=r.thread_id AND r2.id<=r.id) AS seq "
            "FROM replies r WHERE r.id=? AND r.thread_id=?", (post, tid)).fetchone()
        floor_no = 1 + fr["seq"] if fr else 1
        focus_page = max(1, (floor_no - 1) // PER_FLOOR_PAGE + 1)
    elif floor > 1:
        # 客户端按楼层号跳转：只算页码，不额外查库
        focus_page = max(1, (floor - 1) // PER_FLOOR_PAGE + 1)

    posts = []
    # 1 楼永远是楼主正文
    if page == 1:
        posts.append({
            "floor": 1,
            "id": 0,
            "body": t["body"],
            "author": t["author_nick"] or t["author"],
            "handle": t["author_handle"] or "",
            "author_name": t["author_name"] or "",
            "author_avatar": t["author_avatar"] or "",
            "author_id": t["user_id"],
            "level": t["level"] or 1,
            "signature": t["signature"] or "",
            "created_at": t["created_at"],
            "agree_count": 0,
            **_imgs_payload(t["images"]),
            **_files_payload(t["files"]),
            "subs": [],
            "is_op": True,
            "edited_at": t["edited_at"] or 0,
            "can_edit": bool(user and (user["id"] == t["user_id"] or user["is_admin"])),
            "can_delete": _may_delete(user, t["user_id"]),
        })

    offset = (page - 1) * PER_FLOOR_PAGE - (1 if page == 1 else 0)
    offset = max(0, offset)
    rows = c.execute(
        "SELECT r.*, u.name AS author, u.nickname AS author_nick, u.handle AS author_handle, u.signature, u.level, "
        "u.avatar AS author_avatar "
        "FROM replies r JOIN users u ON u.id=r.user_id "
        "WHERE r.thread_id=? AND (r.parent_id IS NULL OR r.parent_id = 0) "
        "ORDER BY r.id LIMIT ? OFFSET ?",
        (tid, PER_FLOOR_PAGE if page > 1 else PER_FLOOR_PAGE - 1, offset)).fetchall()

    # 这一页每层的楼中楼一次查完，别一层一条 SQL。
    ids = [r["id"] for r in rows]
    subs_of = {i: [] for i in ids}
    sub_n = {i: 0 for i in ids}
    if ids:
        marks = ",".join("?" * len(ids))
        for s in c.execute(
            "SELECT r2.*, u.name AS author, u.nickname AS author_nick, u.handle AS author_handle, "
            "u.signature, u.level, u.avatar AS author_avatar "
            "FROM replies r2 JOIN users u ON u.id=r2.user_id "
            "WHERE r2.thread_id=? AND r2.parent_id IN (" + marks + ") ORDER BY r2.id",
            (tid, *ids)).fetchall():
            pid = s["parent_id"]
            sub_n[pid] += 1
            if len(subs_of[pid]) < 10:
                subs_of[pid].append(s)

    base = 1 + (page - 1) * PER_FLOOR_PAGE if page > 1 else 1
    for i, r in enumerate(rows):
        item = _reply_json(r)
        item["floor"] = r["floor_no"] or (base + i + (0 if page > 1 else 1))
        item["is_op"] = r["user_id"] == t["user_id"]
        item["can_edit"] = bool(user and (user["id"] == r["user_id"] or user["is_admin"]))
        item["can_delete"] = _may_delete(user, r["user_id"])
        subs = subs_of.get(r["id"], [])
        item["subs"] = [{
            "id": s["id"],
            "body": s["body"],
            "author": s["author_nick"] or s["author"],
            "handle": s["author_handle"] or "",
            "author_name": s["author"] or "",
            "author_avatar": s["author_avatar"] or "",
            "author_id": s["user_id"],
            "created_at": s["created_at"],
            "edited_at": s["edited_at"] or 0,
            "can_edit": bool(user and (user["id"] == s["user_id"] or user["is_admin"])),
            **_imgs_payload(s["images"]),
            **_files_payload(s["files"]),
            "can_delete": _may_delete(user, s["user_id"]),
        } for s in subs]
        item["sub_count"] = sub_n.get(r["id"], 0)
        posts.append(item)

    liked_reply_ids = set()
    thread_agreed = False
    thread_faved = False
    if user:
        thread_agreed = bool(c.execute(
            "SELECT 1 FROM likes WHERE user_id=? AND target_kind='thread' AND target_id=?",
            (user["id"], tid)).fetchone())
        thread_faved = bool(c.execute(
            "SELECT 1 FROM favorites WHERE user_id=? AND thread_id=?",
            (user["id"], tid)).fetchone())
        # 只查这一页出现的回复，别把这个人历史上赞过的全捞出来。
        rids = [p_["id"] for p_ in posts if p_["id"]]
        for p_ in posts:
            rids.extend(s["id"] for s in p_["subs"])
        if rids:
            marks = ",".join("?" * len(rids))
            liked_reply_ids = {
                r["target_id"] for r in c.execute(
                    "SELECT target_id FROM likes WHERE user_id=? AND target_kind='reply' "
                    "AND target_id IN (" + marks + ")",
                    (user["id"], *rids))}
    for p_ in posts:
        p_["agreed"] = (p_["id"] in liked_reply_ids) if p_["id"] else thread_agreed

    return {
        "thread": {
            "id": t["id"],
            "title": t["title"],
            "author": t["author_nick"] or t["author"],
            "handle": t["author_handle"] or "",
            "author_name": t["author_name"] or "",
            "author_avatar": t["author_avatar"] or "",
            "reply_count": total_replies,
            "view_count": t["view_count"] + 1,
            "created_at": t["created_at"],
            "is_good": bool(t["is_good"]),
            "is_top": bool(t["is_top"]) if "is_top" in t.keys() else False,
            "is_admin": bool(user["is_admin"]) if user else False,
            "owner_id": t["user_id"],
            "agree_count": t["agree_count"],
            "agreed": thread_agreed,
            "faved": thread_faved,
            "can_delete": _may_delete(user, t["user_id"]),
        },
        "posts": posts,
        "page": page,
        "pages": pages,
        "total_floors": total_floors,
        "focus_page": focus_page,
    }


@router.post("/t/{tid}/reply")
def reply(tid: int, p: NewReply, c=Depends(get_conn), user=Depends(require_user)):
    t = c.execute("SELECT * FROM threads WHERE id=?", (tid,)).fetchone()
    if not t:
        raise HTTPException(404, "帖子不存在")
    body = p.body.strip()[:BODY_MAX]
    attach = _norm_files(p.files, c, user)
    if not body and not p.images and not attach:
        raise HTTPException(400, "内容不能为空")
    parent = p.parent_id or 0
    if parent and not c.execute("SELECT 1 FROM replies WHERE id=? AND thread_id=?",
                                (parent, tid)).fetchone():
        parent = 0
    now = int(time.time())
    floor_no = 1
    if not parent:
        mx = c.execute("SELECT MAX(floor_no) AS m FROM replies "
                       "WHERE thread_id=? AND COALESCE(parent_id,0)=0",
                       (tid,)).fetchone()["m"] or 1
        floor_no = int(mx) + 1
    cur = c.execute(
        "INSERT INTO replies(thread_id, body, user_id, created_at, parent_id, images, floor_no, files) "
        "VALUES(?,?,?,?,?,?,?,?)",
        (tid, body, user["id"], now, parent, _save_imgs(p.images), floor_no, _save_files(attach)))
    rid = cur.lastrowid
    if not parent:
        c.execute("UPDATE threads SET reply_count=reply_count+1, updated_at=? WHERE id=?", (now, tid))
    else:
        c.execute("UPDATE threads SET updated_at=? WHERE id=?", (now, tid))
    # 通知：楼中楼通知被回复的那层作者，直接回复通知楼主
    target = t["user_id"]
    if parent:
        pr = c.execute("SELECT user_id FROM replies WHERE id=?", (parent,)).fetchone()
        if pr:
            target = pr["user_id"]
    if target and target != user["id"]:
        c.execute(
            "INSERT INTO notifications(user_id, actor_id, kind, thread_id, reply_id, body, created_at) "
            "VALUES(?,?,?,?,?,?,?)",
            (target, user["id"], "sub" if parent else "reply", tid, rid, body[:120], now))
    _notify_mentions(c, body, user["id"], tid, rid, now, skip={target or 0})
    _refresh_level(c, user["id"])
    c.commit()
    return {"reply_id": rid, "floor": 0 if parent else floor_no}


@router.patch("/t/{tid}")
def edit_thread(tid: int, p: PatchThread, c=Depends(get_conn), user=Depends(require_user)):
    """改标题/正文/图片。只有作者本人和管理员能动。

    不动 updated_at —— 改个错字不该把帖子顶回首页。
    """
    t = c.execute("SELECT * FROM threads WHERE id=?", (tid,)).fetchone()
    if not t:
        raise HTTPException(404, "帖子不存在")
    if t["user_id"] != user["id"] and not user["is_admin"]:
        raise HTTPException(403, "只能改自己的帖子")

    title = (t["title"] or "") if p.title is None else p.title.strip()[:TITLE_MAX]
    body = (t["body"] or "") if p.body is None else p.body.strip()[:BODY_MAX]
    images = _load_imgs(t["images"]) if p.images is None else _norm_imgs(p.images)
    attach = _load_files(t["files"]) if p.files is None else _norm_files(p.files, c, user)
    if not title:
        raise HTTPException(400, "标题要填")
    if not body and not images and not attach:
        raise HTTPException(400, "正文、图片、附件至少留一样")

    now = int(time.time())
    c.execute(
        "UPDATE threads SET title=?, body=?, images=?, files=?, edited_at=? WHERE id=?",
        (title, body, _save_imgs(images), _save_files(attach), now, tid))
    c.commit()
    return {"ok": True, "edited_at": now, "title": title, "images": images}


@router.patch("/c/{cid}")
def edit_reply(cid: int, p: PatchReply, c=Depends(get_conn), user=Depends(require_user)):
    r = c.execute("SELECT * FROM replies WHERE id=?", (cid,)).fetchone()
    if not r:
        raise HTTPException(404, "回复不存在")
    if r["user_id"] != user["id"] and not user["is_admin"]:
        raise HTTPException(403, "只能改自己的回复")

    body = (r["body"] or "") if p.body is None else p.body.strip()[:BODY_MAX]
    images = _load_imgs(r["images"]) if p.images is None else _norm_imgs(p.images)
    attach = _load_files(r["files"]) if p.files is None else _norm_files(p.files, c, user)
    if not body and not images and not attach:
        raise HTTPException(400, "内容不能为空")

    now = int(time.time())
    c.execute("UPDATE replies SET body=?, images=?, files=?, edited_at=? WHERE id=?",
              (body, _save_imgs(images), _save_files(attach), now, cid))
    c.commit()
    return {"ok": True, "edited_at": now}


@router.delete("/t/{tid}")
def delete_thread(tid: int, c=Depends(get_conn), user=Depends(require_user)):
    t = c.execute("SELECT id, user_id, title FROM threads WHERE id=?",
                  (tid,)).fetchone()
    if not t:
        raise HTTPException(404, "帖子不存在")
    if not _may_delete(user, t["user_id"]):
        raise HTTPException(403, "只能删自己的帖子")
    victim = t["user_id"]
    title = t["title"] or ""

    rids = [r["id"] for r in c.execute("SELECT id FROM replies WHERE thread_id=?", (tid,)).fetchall()]
    for rid in rids:
        c.execute("DELETE FROM likes WHERE target_kind='reply' AND target_id=?", (rid,))
        c.execute("DELETE FROM notifications WHERE reply_id=?", (rid,))
    c.execute("DELETE FROM likes WHERE target_kind='thread' AND target_id=?", (tid,))
    c.execute("DELETE FROM notifications WHERE thread_id=?", (tid,))
    c.execute("DELETE FROM favorites WHERE thread_id=?", (tid,))
    c.execute("DELETE FROM history WHERE thread_id=?", (tid,))
    c.execute("DELETE FROM replies WHERE thread_id=?", (tid,))
    c.execute("DELETE FROM threads WHERE id=?", (tid,))
    if victim != user["id"]:
        # 帖子已经没了，thread_id 留空，点通知不会跳去 404
        _notify(c, victim, user["id"], "del", None, None, title,
                int(time.time()))
    c.commit()
    return {"ok": True}


@router.delete("/c/{cid}")
def delete_reply(cid: int, c=Depends(get_conn), user=Depends(require_user)):
    r = c.execute("SELECT id, thread_id, user_id, parent_id FROM replies WHERE id=?",
                  (cid,)).fetchone()
    if not r:
        raise HTTPException(404, "回复不存在")
    if not _may_delete(user, r["user_id"]):
        raise HTTPException(403, "只能删自己的回复")
    trow = c.execute("SELECT title FROM threads WHERE id=?",
                     (r["thread_id"],)).fetchone()

    # 楼层删掉时，挂在它下面的楼中楼一起走
    ids = [cid] + [x["id"] for x in c.execute(
        "SELECT id FROM replies WHERE parent_id=?", (cid,)).fetchall()]
    for rid in ids:
        c.execute("DELETE FROM likes WHERE target_kind='reply' AND target_id=?", (rid,))
        c.execute("DELETE FROM notifications WHERE reply_id=?", (rid,))
        c.execute("DELETE FROM replies WHERE id=?", (rid,))
    if not r["parent_id"]:
        c.execute("UPDATE threads SET reply_count=MAX(reply_count-1, 0), updated_at=? WHERE id=?",
                  (int(time.time()), r["thread_id"]))
    if r["user_id"] != user["id"]:
        _notify(c, r["user_id"], user["id"], "del", r["thread_id"], None,
                "回复被删：" + (trow["title"] if trow else ""), int(time.time()))
    c.commit()
    return {"ok": True}


@router.post("/agree/{kind}/{target_id}")
def agree(kind: str, target_id: int, c=Depends(get_conn), user=Depends(require_user)):
    if kind not in ("thread", "reply"):
        raise HTTPException(400, "kind 只能是 thread 或 reply")
    tbl = "threads" if kind == "thread" else "replies"
    if not c.execute("SELECT 1 FROM " + tbl + " WHERE id=?", (target_id,)).fetchone():
        raise HTTPException(404, "对象不存在")
    now = int(time.time())
    hit = c.execute("SELECT 1 FROM likes WHERE user_id=? AND target_kind=? AND target_id=?",
                    (user["id"], kind, target_id)).fetchone()
    if hit:
        c.execute("DELETE FROM likes WHERE user_id=? AND target_kind=? AND target_id=?",
                  (user["id"], kind, target_id))
        on = False
        if kind == "reply":
            c.execute("UPDATE replies SET agree_count=MAX(0, agree_count-1) WHERE id=?", (target_id,))
        else:
            c.execute("UPDATE threads SET agree_count=MAX(0, agree_count-1) WHERE id=?", (target_id,))
    else:
        c.execute("INSERT INTO likes(user_id, target_kind, target_id, created_at) VALUES(?,?,?,?)",
                  (user["id"], kind, target_id, now))
        on = True
        reply_id = target_id if kind == "reply" else 0
        if kind == "reply":
            c.execute("UPDATE replies SET agree_count=agree_count+1 WHERE id=?", (target_id,))
            r = c.execute("SELECT user_id, thread_id FROM replies WHERE id=?", (target_id,)).fetchone()
            owner, ttid = (r["user_id"], r["thread_id"]) if r else (None, None)
        else:
            c.execute("UPDATE threads SET agree_count=agree_count+1 WHERE id=?", (target_id,))
            r = c.execute("SELECT user_id FROM threads WHERE id=?", (target_id,)).fetchone()
            owner, ttid = (r["user_id"] if r else None), target_id
        if owner and owner != user["id"]:
            dup = c.execute(
                "SELECT 1 FROM notifications WHERE user_id=? AND actor_id=? AND kind='agree' "
                "AND thread_id=? AND reply_id=?",
                (owner, user["id"], ttid, reply_id)).fetchone()
            if not dup:
                c.execute(
                    "INSERT INTO notifications(user_id, actor_id, kind, thread_id, reply_id, body, created_at) "
                    "VALUES(?,?,?,?,?,?,?)",
                    (owner, user["id"], "agree", ttid, reply_id, "", now))
    c.commit()
    return {"agreed": on}


# ---------------------------------------------------------------- 图片


def _sniff(raw: bytes):
    if raw[:3] == b"\xff\xd8\xff":
        return "jpg"
    if raw[:8] == b"\x89PNG\r\n\x1a\n":
        return "png"
    if raw[:6] in (b"GIF87a", b"GIF89a"):
        return "gif"
    if raw[:4] == b"RIFF" and raw[8:12] == b"WEBP":
        return "webp"
    return None


# 管理员一键替换用的占位图：源图固定叫 replaced.jpg，每次替换复制一份带时间戳的，
# 这样 URL 会变，客户端不会拿旧缓存（cached_network_image 是按 URL 存盘的）。
REPLACED_SRC = os.path.join(UPLOAD_DIR, "na", "replaced.jpg")
REPLACED_DIR = os.path.join(UPLOAD_DIR, "na")


def _fresh_placeholder():
    """复制一份新的占位图，顺手清掉旧的，最多留 5 个。"""
    name = "replaced-%d.jpg" % int(time.time() * 1000)
    shutil.copyfile(REPLACED_SRC, os.path.join(REPLACED_DIR, name))
    old = sorted(f for f in os.listdir(REPLACED_DIR) if f.startswith("replaced-"))
    for f in old[:-5]:
        try:
            os.remove(os.path.join(REPLACED_DIR, f))
        except OSError:
            pass
    return "/img/na/" + name


@router.post("/t/{tid}/replace-images")
def replace_images(tid: int, c=Depends(get_conn), user=Depends(require_user)):
    """把帖子和它下面所有楼层的图都换成占位图，admin 专用。"""
    if not user["is_admin"]:
        raise HTTPException(403, "只有管理员能替换")
    if not os.path.exists(REPLACED_SRC):
        raise HTTPException(503, "服务器上还没放替换图")
    t = c.execute("SELECT id, images FROM threads WHERE id=?", (tid,)).fetchone()
    if not t:
        raise HTTPException(404, "帖子不存在")
    changed = 0
    url = _fresh_placeholder()

    def wipe(row, table):
        """张数保持不变，只把每张换成占位图，版面不会塌。"""
        imgs = _load_imgs(row["images"])
        if not imgs:
            return 0
        c.execute(
            "UPDATE %s SET images=? WHERE id=?" % table,
            (_save_imgs([url] * len(imgs)), row["id"]),
        )
        return len(imgs)

    changed += wipe(t, "threads")
    for r in c.execute(
        "SELECT id, images FROM replies WHERE thread_id=?", (tid,)
    ).fetchall():
        changed += wipe(r, "replies")
    c.commit()
    return {"ok": True, "changed": changed, "url": url}


@router.post("/upload")
def upload(p: NewImage, user=Depends(require_user)):
    data = p.data.split(",", 1)[-1]
    # 先按 base64 长度兜一道：不然一串几百 MB 的 data 会先被整个读进内存再解码。
    if len(data) > (MAX_ANIM // 3) * 4 + 256:
        raise HTTPException(413, "单张图别超过 %dMB" % (MAX_ANIM // 1024 // 1024))
    try:
        raw = base64.b64decode(data, validate=False)
    except Exception:
        raise HTTPException(400, "图片数据坏了")
    if not raw:
        raise HTTPException(400, "空文件")
    ext = _sniff(raw)
    if not ext:
        raise HTTPException(400, "只收 jpg / png / gif / webp")
    # 动图压不了，放宽到 10MB；静态图还是 5MB。
    limit = MAX_ANIM if ext in ("gif", "webp") else MAX_IMAGE
    if len(raw) > limit:
        raise HTTPException(413, "单张图别超过 %dMB" % (limit // 1024 // 1024))
    import hashlib
    digest = hashlib.sha256(raw).hexdigest()
    sub = os.path.join(UPLOAD_DIR, digest[:2])
    os.makedirs(sub, exist_ok=True)
    fn = digest[:20] + "." + ext
    path = os.path.join(sub, fn)
    if not os.path.exists(path):
        with open(path, "wb") as f:
            f.write(raw)
    return {"url": "/img/%s/%s" % (digest[:2], fn)}


def _today_start():
    """本地时区的今天零点。服务器按 CST 跑，别用 UTC 切天。"""
    return int((time.time() + 8 * 3600) // 86400 * 86400 - 8 * 3600)


@router.post("/file")
async def upload_file(f: UploadFile = File(...), c=Depends(get_conn),
                      user=Depends(require_user)):
    """附件走 multipart 直接落盘。500MB 的包不能先 base64 再解码——那样内存先炸。"""
    cap = filesvc.MAX_BYTES
    if f.size is not None and f.size > cap:
        raise HTTPException(413, "单个文件别超过 %dMB" % filesvc.MAX_MB)
    n, used = filesvc.quota(c, user["id"], _today_start())
    if n >= filesvc.PER_DAY:
        raise HTTPException(429, "今天传够 %d 个了，明天再说" % filesvc.PER_DAY)
    if used >= filesvc.PER_DAY_MB * 1024 * 1024:
        raise HTTPException(429, "今天的附件额度用完了")

    name = filesvc.clean_name(f.filename)
    try:
        digest, size, _ = await filesvc.ingest(f, cap)
    except filesvc.TooBig:
        raise HTTPException(413, "单个文件别超过 %dMB" % filesvc.MAX_MB)
    except filesvc.Empty:
        raise HTTPException(400, "空文件")

    row = c.execute("SELECT name, size FROM files WHERE digest=?", (digest,)).fetchone()
    if not row:
        c.execute(
            "INSERT INTO files(digest, name, size, mime, uploader, created_at) "
            "VALUES(?,?,?,?,?,?)",
            (digest, name, size, filesvc.guess_mime(name), user["id"], int(time.time())))
        c.commit()
        row = c.execute("SELECT name, size FROM files WHERE digest=?", (digest,)).fetchone()
    return {"url": "/f/" + digest, "name": row["name"], "size": row["size"]}


def serve_file(digest: str, c=Depends(get_conn)):
    """下载。一律当附件给，不内联渲染——传个 html 上来也不会在本站跑脚本。"""
    if not re.fullmatch(r"[0-9a-f]{20}", digest or ""):
        raise HTTPException(404)
    row = c.execute("SELECT name, mime FROM files WHERE digest=?", (digest,)).fetchone()
    path = filesvc.path_of(digest)
    if not row or not os.path.exists(path):
        raise HTTPException(404, "文件不在了")
    try:
        c.execute("UPDATE files SET downloads=downloads+1 WHERE digest=?", (digest,))
        c.commit()
    except Exception:
        pass
    return FileResponse(
        path, filename=row["name"],
        media_type=row["mime"] or "application/octet-stream",
        headers={"X-Content-Type-Options": "nosniff",
                 "Cache-Control": "public, max-age=31536000, immutable"})


# ---------------------------------------------------------------- 搜索 / 通知 / 收藏 / 历史


def _brief(r, user=None):
    return {
        "id": r["id"],
        "title": r["title"],
        "excerpt": _excerpt(r["body"] if "body" in r.keys() else ""),
        "author": r["author_nick"] or r["author"],
        "handle": r["author_handle"] or "",
        "reply_count": r["reply_count"],
        "view_count": r["view_count"],
        "is_good": bool(r["is_good"]),
        "is_top": bool(r["is_top"]) if "is_top" in r.keys() else False,
        "can_delete": _may_delete(user, r["user_id"]),
        "updated_at": r["updated_at"],
        "edited_at": r["edited_at"] or 0,
        **_imgs_payload(r["images"] if "images" in r.keys() else None),
        **_files_payload(r["files"] if "files" in r.keys() else None),
    }


@router.get("/search")
def search(q: str = "", page: int = 1, c=Depends(get_conn), user=Depends(optional_user)):
    q = q.strip()
    page = max(1, page)
    if not q:
        return {"items": [], "page": 1, "total": 0}
    like = "%" + q.replace("\\", "").replace("%", "").replace("_", "") + "%"
    where = "(t.title LIKE ? OR t.body LIKE ?)"
    total = c.execute(
        "SELECT COUNT(*) AS n FROM threads t WHERE " + where,
        (like, like)).fetchone()["n"]
    rows = c.execute(
        "SELECT t.id, t.title, t.body, t.created_at, t.updated_at, t.edited_at, t.reply_count, t.view_count, "
        "t.is_good, t.images, t.files, t.user_id, u.name AS author, u.nickname AS author_nick, u.handle AS author_handle "
        "FROM threads t JOIN users u ON u.id=t.user_id "
        "WHERE " + where + " ORDER BY t.updated_at DESC LIMIT ? OFFSET ?",
        (like, like, PER_PAGE, (page - 1) * PER_PAGE)).fetchall()
    return {"items": [_brief(r, user) for r in rows], "page": page, "total": total}


@router.get("/mention/suggest")
def mention_suggest(q: str = "", c=Depends(get_conn), user=Depends(optional_user)):
    """@ 输入时的候选：handle / 用户名 / 昵称都能搜到。"""
    q = q.strip().lstrip("@")
    if not q:
        # 光敲一个 @ 时，先给几个活跃的。
        rows = c.execute(
            "SELECT id, name, nickname, handle, avatar, level FROM users "
            "ORDER BY level DESC, id ASC LIMIT 8").fetchall()
    else:
        like = "%" + q.replace("\\", "").replace("%", "").replace("_", "") + "%"
        rows = c.execute(
            "SELECT id, name, nickname, handle, avatar, level FROM users "
            "WHERE name LIKE ? OR nickname LIKE ? OR handle LIKE ? "
            "ORDER BY level DESC, id ASC LIMIT 8", (like, like, like)).fetchall()
    return {"items": [{
        "id": r["id"],
        "name": r["name"],
        "nickname": r["nickname"] or "",
        "handle": r["handle"] or r["name"],
        "avatar": r["avatar"] or "",
        "level": r["level"],
    } for r in rows]}


class ReadReq(BaseModel):
    id: Optional[int] = None


# ---------------------------------------------------------------- 管理 / 举报


def _need_admin(user):
    if not user or not user["is_admin"]:
        raise HTTPException(403, "没有权限")


class ReportReq(BaseModel):
    thread_id: Optional[int] = None
    reply_id: Optional[int] = None
    reason: str = ""


@router.post("/admin/t/{tid}/top")
def admin_top(tid: int, c=Depends(get_conn), user=Depends(require_user)):
    """置顶开关。置顶的帖子在时间线里排最前。"""
    _need_admin(user)
    t = c.execute("SELECT is_top FROM threads WHERE id=?", (tid,)).fetchone()
    if not t:
        raise HTTPException(404, "帖子不存在")
    on = 0 if t["is_top"] else 1
    c.execute("UPDATE threads SET is_top=? WHERE id=?", (on, tid))
    c.commit()
    return {"is_top": bool(on)}


@router.post("/admin/t/{tid}/good")
def admin_good(tid: int, c=Depends(get_conn), user=Depends(require_user)):
    """加精开关。开的时候通知作者，撤精就把那条通知收回去。"""
    _need_admin(user)
    t = c.execute("SELECT is_good, user_id, title FROM threads WHERE id=?",
                  (tid,)).fetchone()
    if not t:
        raise HTTPException(404, "帖子不存在")
    on = 0 if t["is_good"] else 1
    c.execute("UPDATE threads SET is_good=? WHERE id=?", (on, tid))
    if on and t["user_id"] != user["id"]:
        _notify(c, t["user_id"], user["id"], "good", tid, None,
                t["title"] or "", int(time.time()))
    elif not on:
        c.execute("DELETE FROM notifications WHERE kind='good' AND thread_id=?",
                  (tid,))
    c.commit()
    return {"is_good": bool(on)}


@router.post("/report")
def report(p: ReportReq, c=Depends(get_conn), user=Depends(require_user)):
    if not p.thread_id and not p.reply_id:
        raise HTTPException(400, "要指明举报的帖子或楼层")
    tid = p.thread_id
    if p.reply_id:
        r = c.execute("SELECT thread_id FROM replies WHERE id=?", (p.reply_id,)).fetchone()
        if not r:
            raise HTTPException(404, "楼层不存在")
        tid = r["thread_id"]
    row = c.execute("SELECT 1 FROM reports WHERE user_id=? AND handled=0 AND "
                    "COALESCE(thread_id,0)=? AND COALESCE(reply_id,0)=?",
                    (user["id"], tid or 0, p.reply_id or 0)).fetchone()
    if row:
        return {"ok": True, "duplicate": True}
    c.execute("INSERT INTO reports(user_id, thread_id, reply_id, reason, created_at) "
              "VALUES(?,?,?,?,?)",
              (user["id"], tid, p.reply_id, p.reason.strip()[:200], int(time.time())))
    c.commit()
    return {"ok": True, "duplicate": False}


@router.get("/admin/reports/count")
def admin_reports_count(c=Depends(get_conn), user=Depends(require_user)):
    """抽屉角标用，只要个数字。"""
    _need_admin(user)
    n = c.execute("SELECT COUNT(*) AS n FROM reports WHERE handled=0").fetchone()["n"]
    return {"open": n}


@router.get("/admin/reports")
def admin_reports(page: int = 1, c=Depends(get_conn), user=Depends(require_user)):
    _need_admin(user)
    page = max(1, page)
    rows = c.execute(
        "SELECT r.*, u.name AS reporter, u.nickname AS reporter_nick, "
        "t.title AS thread_title, t.body AS thread_body, "
        "p.body AS reply_body, p.thread_id AS reply_thread "
        "FROM reports r JOIN users u ON u.id=r.user_id "
        "LEFT JOIN threads t ON t.id=r.thread_id "
        "LEFT JOIN replies p ON p.id=r.reply_id "
        "WHERE r.handled=0 ORDER BY r.id DESC LIMIT ? OFFSET ?",
        (PER_PAGE, (page - 1) * PER_PAGE)).fetchall()
    total = c.execute("SELECT COUNT(*) AS n FROM reports WHERE handled=0").fetchone()["n"]
    return {"total": total, "page": page, "items": [{
        "id": r["id"],
        "reporter": r["reporter_nick"] or r["reporter"],
        "thread_id": r["thread_id"] or r["reply_thread"],
        "reply_id": r["reply_id"],
        "thread_title": r["thread_title"] or "",
        "text": (r["reply_body"] or r["thread_body"] or "")[:200],
        "reason": r["reason"],
        "created_at": r["created_at"],
    } for r in rows]}


@router.post("/admin/reports/{rid}")
def admin_report_handle(rid: int, keep: bool = False,
                        c=Depends(get_conn), user=Depends(require_user)):
    """处理举报：默认删内容，keep=true 表示内容没问题，只把举报关掉。"""
    _need_admin(user)
    r = c.execute("SELECT * FROM reports WHERE id=?", (rid,)).fetchone()
    if not r:
        raise HTTPException(404, "举报不存在")
    if not keep:
        if r["reply_id"]:
            c.execute("DELETE FROM replies WHERE id=?", (r["reply_id"],))
            c.execute("DELETE FROM notifications WHERE reply_id=?", (r["reply_id"],))
            c.execute("UPDATE threads SET reply_count=MAX(reply_count-1,0) WHERE id=?",
                      (r["thread_id"],))
        elif r["thread_id"]:
            c.execute("DELETE FROM replies WHERE thread_id=?", (r["thread_id"],))
            c.execute("DELETE FROM notifications WHERE thread_id=?", (r["thread_id"],))
            c.execute("DELETE FROM threads WHERE id=?", (r["thread_id"],))
    c.execute("UPDATE reports SET handled=1, handled_by=? WHERE id=?", (user["id"], rid))
    # 同一条内容上的其它举报一起关掉
    c.execute("UPDATE reports SET handled=1, handled_by=? WHERE handled=0 AND "
              "COALESCE(thread_id,0)=? AND COALESCE(reply_id,0)=?",
              (user["id"], r["thread_id"] or 0, r["reply_id"] or 0))
    c.commit()
    return {"ok": True, "deleted": not keep}


# ---------------------------------------------------------------- 需求单

class FeatureReq(BaseModel):
    title: str
    body: str = ""


@router.post("/feature-request")
def feature_request(p: FeatureReq, c=Depends(get_conn), user=Depends(require_user)):
    """普通用户提一条「想要的新功能」。"""
    title = (p.title or "").strip()[:60]
    body = (p.body or "").strip()[:2000]
    if len(title) < 4:
        raise HTTPException(400, "标题再写清楚一点")
    now = int(time.time())
    # 一天三条上限，够正常人用了
    n = c.execute("SELECT COUNT(*) AS n FROM feature_requests "
                  "WHERE user_id=? AND created_at>?", (user["id"], now - 86400)).fetchone()["n"]
    if n >= 3:
        raise HTTPException(429, "今天提得有点多，明天再来")
    # 同一个人重复提同一个标题，还没处理的就不要再塞一条
    dup = c.execute("SELECT 1 FROM feature_requests "
                    "WHERE user_id=? AND status=0 AND title=?", (user["id"], title)).fetchone()
    if dup:
        return {"ok": True, "duplicate": True}
    c.execute("INSERT INTO feature_requests(user_id, title, body, created_at) VALUES(?,?,?,?)",
              (user["id"], title, body, now))
    c.commit()
    return {"ok": True, "duplicate": False}


@router.get("/feature-requests/mine")
def my_feature_requests(c=Depends(get_conn), user=Depends(require_user)):
    """自己提过的单子，顺带看管理员怎么回的。"""
    rows = c.execute(
        "SELECT * FROM feature_requests WHERE user_id=? ORDER BY id DESC LIMIT 20",
        (user["id"],)).fetchall()
    return {"items": [_feature_json(r) for r in rows]}


def _feature_json(r):
    return {
        "id": r["id"],
        "title": r["title"],
        "body": r["body"],
        "status": r["status"],
        "note": r["note"],
        "created_at": r["created_at"],
        "handled_at": r["handled_at"],
    }


@router.get("/admin/feature-requests/count")
def admin_feature_count(c=Depends(get_conn), user=Depends(require_user)):
    """抽屉角标用。"""
    _need_admin(user)
    n = c.execute("SELECT COUNT(*) AS n FROM feature_requests WHERE status=0").fetchone()["n"]
    return {"open": n}


@router.get("/admin/feature-requests")
def admin_feature_requests(page: int = 1, done: bool = False,
                           c=Depends(get_conn), user=Depends(require_user)):
    _need_admin(user)
    page = max(1, page)
    where = "f.status<>0" if done else "f.status=0"
    rows = c.execute(
        "SELECT f.*, u.name AS author, u.nickname AS author_nick, u.handle AS author_handle "
        "FROM feature_requests f JOIN users u ON u.id=f.user_id "
        "WHERE " + where + " ORDER BY f.id DESC LIMIT ? OFFSET ?",
        (PER_PAGE, (page - 1) * PER_PAGE)).fetchall()
    total = c.execute("SELECT COUNT(*) AS n FROM feature_requests WHERE " +
                      ("status<>0" if done else "status=0")).fetchone()["n"]
    items = []
    for r in rows:
        d = _feature_json(r)
        d["author"] = r["author_nick"] or r["author"]
        d["handle"] = r["author_handle"] or ""
        d["user_id"] = r["user_id"]
        items.append(d)
    return {"total": total, "page": page, "items": items}


@router.post("/admin/feature-requests/{fid}")
def admin_feature_handle(fid: int, status: int = 1, note: str = "",
                         c=Depends(get_conn), user=Depends(require_user)):
    """处理需求单：1 采纳，2 不做；note 是给提交人的一句话回复。"""
    _need_admin(user)
    if status not in (0, 1, 2):
        raise HTTPException(400, "状态只能是 0/1/2")
    r = c.execute("SELECT id FROM feature_requests WHERE id=?", (fid,)).fetchone()
    if not r:
        raise HTTPException(404, "需求单不存在")
    c.execute("UPDATE feature_requests SET status=?, note=?, handled_by=?, handled_at=? WHERE id=?",
              (status, (note or "").strip()[:500], user["id"],
               int(time.time()) if status else None, fid))
    c.commit()
    return {"ok": True, "status": status}


@router.get("/notifications")
def notifications(page: int = 1, c=Depends(get_conn), user=Depends(require_user)):
    page = max(1, page)
    rows = c.execute(
        "SELECT n.*, u.name AS actor, u.nickname AS actor_nick, u.handle AS actor_handle, t.title AS thread_title "
        "FROM notifications n JOIN users u ON u.id=n.actor_id "
        "LEFT JOIN threads t ON t.id=n.thread_id "
        "WHERE n.user_id=? ORDER BY n.id DESC LIMIT ? OFFSET ?",
        (user["id"], PER_PAGE, (page - 1) * PER_PAGE)).fetchall()
    unread = c.execute(
        "SELECT COUNT(*) AS n FROM notifications WHERE user_id=? AND is_read=0",
        (user["id"],)).fetchone()["n"]
    return {"unread": unread, "page": page, "items": [{
        "id": r["id"],
        "kind": r["kind"],
        "actor": r["actor_nick"] or r["actor"],
        "handle": r["actor_handle"] or "",
        "actor_id": r["actor_id"],
        "thread_id": r["thread_id"],
        "thread_title": r["thread_title"] or "",
        "reply_id": r["reply_id"],
        "body": r["body"],
        "is_read": bool(r["is_read"]),
        "created_at": r["created_at"],
    } for r in rows]}


@router.post("/notifications/read")
def notifications_read(c=Depends(get_conn), user=Depends(require_user)):
    c.execute("UPDATE notifications SET is_read=1 WHERE user_id=?", (user["id"],))
    c.commit()
    return {"ok": True}


@router.post("/fav/{tid}")
def fav(tid: int, c=Depends(get_conn), user=Depends(require_user)):
    if not c.execute("SELECT 1 FROM threads WHERE id=?", (tid,)).fetchone():
        raise HTTPException(404, "帖子不存在")
    hit = c.execute("SELECT 1 FROM favorites WHERE user_id=? AND thread_id=?",
                    (user["id"], tid)).fetchone()
    if hit:
        c.execute("DELETE FROM favorites WHERE user_id=? AND thread_id=?", (user["id"], tid))
        on = False
    else:
        c.execute("INSERT INTO favorites(user_id, thread_id, created_at) VALUES(?,?,?)",
                  (user["id"], tid, int(time.time())))
        on = True
    c.commit()
    return {"faved": on}


@router.get("/favorites")
def favorites(page: int = 1, c=Depends(get_conn), user=Depends(require_user)):
    page = max(1, page)
    rows = c.execute(
        "SELECT t.id, t.title, t.body, t.created_at, t.updated_at, t.edited_at, t.reply_count, t.view_count, "
        "t.is_good, t.images, t.files, t.user_id, u.name AS author, u.nickname AS author_nick, u.handle AS author_handle "
        "FROM favorites fa JOIN threads t ON t.id=fa.thread_id "
        "JOIN users u ON u.id=t.user_id "
        "WHERE fa.user_id=? ORDER BY fa.created_at DESC LIMIT ? OFFSET ?",
        (user["id"], PER_PAGE, (page - 1) * PER_PAGE)).fetchall()
    return {"items": [_brief(r, user) for r in rows], "page": page}


@router.get("/history")
def history(page: int = 1, c=Depends(get_conn), user=Depends(require_user)):
    page = max(1, page)
    rows = c.execute(
        "SELECT t.id, t.title, t.body, t.created_at, t.updated_at, t.edited_at, t.reply_count, t.view_count, "
        "t.is_good, t.images, t.files, t.user_id, u.name AS author, u.nickname AS author_nick, u.handle AS author_handle "
        "FROM history h JOIN threads t ON t.id=h.thread_id "
        "JOIN users u ON u.id=t.user_id "
        "WHERE h.user_id=? ORDER BY h.viewed_at DESC LIMIT ? OFFSET ?",
        (user["id"], PER_PAGE, (page - 1) * PER_PAGE)).fetchall()
    return {"items": [_brief(r, user) for r in rows], "page": page}


@router.get("/u/{name}")
def user_page(name: str, page: int = 1, c=Depends(get_conn), user=Depends(optional_user)):
    raw = name.strip().lstrip("@")
    u = c.execute("SELECT * FROM users WHERE name=? OR handle=?",
                  (raw, raw.lower())).fetchone()
    if not u and raw.isdigit():  # 也认 UID（显示的那个号）和内部 id
        u = c.execute("SELECT * FROM users WHERE uid=? OR id=?",
                      (int(raw), int(raw))).fetchone()
    if not u:  # 昵称也认，但只在唯一时认，免得撞名认错人
        rows = c.execute("SELECT * FROM users WHERE nickname=?", (raw,)).fetchall()
        if len(rows) == 1:
            u = rows[0]
    if not u:
        raise HTTPException(404, "用户不存在")
    page = max(1, page)
    info = user_json(u)
    info["created_at"] = u["created_at"]
    info["thread_count"] = c.execute(
        "SELECT COUNT(*) AS n FROM threads WHERE user_id=?", (u["id"],)).fetchone()["n"]
    info["reply_count"] = c.execute(
        "SELECT COUNT(*) AS n FROM replies WHERE user_id=?", (u["id"],)).fetchone()["n"]
    info["follow_count"] = c.execute(
        "SELECT COUNT(*) AS n FROM follows WHERE target_id=?", (u["id"],)).fetchone()["n"]
    info["following_count"] = c.execute(
        "SELECT COUNT(*) AS n FROM follows WHERE follower_id=?", (u["id"],)).fetchone()["n"]
    info["is_following"] = bool(user and c.execute(
        "SELECT 1 FROM follows WHERE follower_id=? AND target_id=?",
        (user["id"], u["id"])).fetchone())
    rows = c.execute(
        "SELECT t.id, t.title, t.body, t.created_at, t.updated_at, t.edited_at, t.reply_count, t.view_count, "
        "t.is_good, t.images, t.files, t.user_id, u.name AS author, u.nickname AS author_nick, u.handle AS author_handle "
        "FROM threads t JOIN users u ON u.id=t.user_id "
        "WHERE t.user_id=? ORDER BY t.updated_at DESC LIMIT ? OFFSET ?",
        (u["id"], PER_PAGE, (page - 1) * PER_PAGE)).fetchall()
    return {"user": info, "items": [_brief(r, user) for r in rows], "page": page}


@router.get("/me/following")
def my_following(c=Depends(get_conn), user=Depends(require_user)):
    rows = c.execute(
        "SELECT u.* FROM follows fo JOIN users u ON u.id=fo.target_id "
        "WHERE fo.follower_id=? ORDER BY fo.created_at DESC", (user["id"],)).fetchall()
    return {"items": [user_json(r) for r in rows]}


@router.get("/me/followers")
def my_followers(c=Depends(get_conn), user=Depends(require_user)):
    rows = c.execute(
        "SELECT u.* FROM follows fo JOIN users u ON u.id=fo.follower_id "
        "WHERE fo.target_id=? ORDER BY fo.created_at DESC", (user["id"],)).fetchall()
    return {"items": [user_json(r) for r in rows]}


@router.post("/u/{name}/follow")
def follow_user(name: str, c=Depends(get_conn), user=Depends(require_user)):
    u = c.execute("SELECT id FROM users WHERE name=? OR handle=?",
                  (name, name.strip().lstrip("@").lower())).fetchone()
    if not u:
        raise HTTPException(404, "用户不存在")
    if u["id"] == user["id"]:
        raise HTTPException(400, "不用关注自己")
    c.execute("INSERT OR IGNORE INTO follows(follower_id, target_id, created_at) VALUES(?,?,?)",
              (user["id"], u["id"], int(time.time())))
    c.commit()
    n = c.execute("SELECT COUNT(*) AS n FROM follows WHERE target_id=?", (u["id"],)).fetchone()["n"]
    return {"following": True, "follow_count": n}


@router.delete("/u/{name}/follow")
def unfollow_user(name: str, c=Depends(get_conn), user=Depends(require_user)):
    u = c.execute("SELECT id FROM users WHERE name=? OR handle=?",
                  (name, name.strip().lstrip("@").lower())).fetchone()
    if not u:
        raise HTTPException(404, "用户不存在")
    c.execute("DELETE FROM follows WHERE follower_id=? AND target_id=?",
              (user["id"], u["id"]))
    c.commit()
    n = c.execute("SELECT COUNT(*) AS n FROM follows WHERE target_id=?", (u["id"],)).fetchone()["n"]
    return {"following": False, "follow_count": n}


class ProfilePatch(BaseModel):
    nickname: Optional[str] = None
    handle: Optional[str] = None
    signature: Optional[str] = None
    avatar: Optional[str] = None
    cover: Optional[str] = None


@router.patch("/me")
def update_me(p: ProfilePatch, c=Depends(get_conn), user=Depends(require_user)):
    sets, vals = [], []
    if p.nickname is not None:
        n = p.nickname.strip()[:20]
        if not n:
            raise HTTPException(400, "昵称不能为空")
        sets.append("nickname=?")
        vals.append(n)
    if p.handle is not None:
        h = p.handle.strip().lstrip("@").lower()
        if not HANDLE_RE.fullmatch(h):
            raise HTTPException(400, "标识只能用小写字母、数字、下划线，3–16 位")
        if h in HANDLE_RESERVED:
            raise HTTPException(400, "这个标识留着了，换一个")
        row = c.execute("SELECT id FROM users WHERE handle=?", (h,)).fetchone()
        if row and row["id"] != user["id"]:
            raise HTTPException(409, "这个标识被人占了")
        sets.append("handle=?")
        vals.append(h)
    if p.signature is not None:
        sets.append("signature=?")
        vals.append(p.signature.strip()[:80])
    if p.avatar is not None:
        sets.append("avatar=?")
        vals.append(p.avatar.strip()[:300])
    if p.cover is not None:
        cv = p.cover.strip()[:300]
        if cv and not cv.startswith("/img/"):
            raise HTTPException(400, "封面只收站内图片")
        sets.append("cover=?")
        vals.append(cv)
    if sets:
        vals.append(user["id"])
        c.execute("UPDATE users SET " + ", ".join(sets) + " WHERE id=?", vals)
        c.commit()
    return {"user": user_json(_load_user(c, user["id"]))}


# ---------------------------------------------------------------- 预置


def seed():
    """空库时只建管理员。站点本身就是唯一的一层，没有板块可塞。"""
    ensure_admin()

@router.get("/about")
def about(c=Depends(get_conn)):
    """关于页用的几个数：成员、主题、回复、建站时间。"""
    u = c.execute("SELECT COUNT(*) AS n, MIN(created_at) AS t FROM users").fetchone()
    th = c.execute("SELECT COUNT(*) AS n FROM threads").fetchone()["n"]
    rp = c.execute("SELECT COUNT(*) AS n FROM replies").fetchone()["n"]
    return {"users": u["n"], "threads": th, "replies": rp,
            "since": u["t"] or 0}


class FriendReq(BaseModel):
    q: str = ""


@router.get("/friends")
def friends(c=Depends(get_conn), user=Depends(optional_user)):
    """关于页的致谢名单，按挂上去的先后。"""
    rows = c.execute(
        "SELECT u.*, f.note AS note FROM friends f JOIN users u ON u.id=f.user_id "
        "ORDER BY f.created_at ASC, f.user_id ASC").fetchall()
    items = []
    for r in rows:
        d = user_json(r)
        d["note"] = r["note"] or ""
        items.append(d)
    return {"items": items, "can_manage": bool(user and user["is_admin"])}


@router.post("/friends")
def friend_add(req: FriendReq, c=Depends(get_conn), user=Depends(require_user)):
    """管理员把人挂上去。认用户名 / @标识 / 昵称 / UID。"""
    _need_admin(user)
    raw = req.q.strip().lstrip("@")
    if not raw:
        raise HTTPException(400, "写个名字")
    u = c.execute("SELECT * FROM users WHERE name=? OR handle=?",
                  (raw, raw.lower())).fetchone()
    if not u and raw.isdigit():
        u = c.execute("SELECT * FROM users WHERE uid=? OR id=?",
                      (int(raw), int(raw))).fetchone()
    if not u:
        rows = c.execute("SELECT * FROM users WHERE nickname=?", (raw,)).fetchall()
        if len(rows) == 1:
            u = rows[0]
    if not u:
        raise HTTPException(404, "没这个人")
    c.execute("INSERT OR IGNORE INTO friends (user_id, note, created_at) VALUES (?, '', ?)",
              (u["id"], int(time.time())))
    c.commit()
    return {"ok": True, "user": user_json(u)}


# ---------------------------------------------------------------- 站点自述 / 清单 / 登记
# PLAN-5-STEPS 第 3 段：每座站都能自述，主站存目录、分配 site_id，
# 客户端拿到清单就能认站，不用人肉配。第 2 段的公钥、黑名单状态也在这里。

API_VERSION = sites.API_VERSION
CAPABILITIES = ["jwt-eddsa", "blacklist", "meta", "manifest", "sites", "register"]


@router.get("/meta")
def site_meta():
    """小站靠这个认人：接口版本、site_id、能力位、验签公钥。

    字段和 /.well-known/bbs.json 的一条对齐，客户端两处用同一套解析。
    """
    me = sites.self_site()
    return {
        **me,
        # 老客户端和 blacklist 拉取读的是 site_id / base_url，保留这两个名字。
        "site_id": me["id"],
        "base_url": me["url"],
        "schema": sites.SCHEMA,
        "api": API_VERSION,
        "capabilities": CAPABILITIES,
        "public_key": auth.public_pem(),
        "blacklist": blacklist.status(),
    }


@router.get("/sites")
def sites_catalog(c=Depends(get_conn)):
    """主站目录。格式与 /.well-known/bbs.json 相同，客户端可直接导入。"""
    return sites.catalog(c)


class SiteRegisterReq(BaseModel):
    url: str = ""
    site_id: str = ""
    name: str = ""
    description: str = ""
    endpoints: List[Any] = []
    lang: str = ""
    icon: str = ""
    tags: List[str] = []
    open: bool = True
    contact: str = ""


@router.post("/sites/register")
def sites_register(req: SiteRegisterReq, request: Request, c=Depends(get_conn)):
    """登记一座小站。地址必填，其余从对方 /meta 补齐。

    幂等：同一个地址重复登记只更新内容，不会分到新 id。
    """
    ip = (request.client.host if request.client else "") or ""
    if not sites.allow_register(ip):
        raise HTTPException(429, "登记太频繁了，过一会儿再试")
    try:
        it, created, need_config = sites.register(c, req.model_dump())
    except sites.ConflictError as e:
        raise HTTPException(409, str(e))
    except ValueError as e:
        raise HTTPException(400, str(e))
    # 对方 /meta 里的 id 跟主站分配的不一样：要么它没填，要么填错了。
    # 自动登记的小站会把这个 id 写进自己的库，人手改配置也行。
    return {
        "ok": True,
        "created": created,
        "site_id": it["id"],
        "site": it,
        "need_config": need_config,
        "hint": "把 site_id 写进对方 site.json 的 site.site_id，或在对方配 master_url 让它自己登记",
    }


@router.delete("/sites/{sid}")
def sites_delete(sid: str, c=Depends(get_conn), user=Depends(require_user)):
    """从目录里摘掉一座站。只动目录，不碰对方的库。"""
    _need_admin(user)
    row = c.execute("SELECT site_id FROM sites WHERE site_id=?", (sid,)).fetchone()
    if not row:
        raise HTTPException(404, "没这个站")
    c.execute("DELETE FROM sites WHERE site_id=?", (sid,))
    c.commit()
    return {"ok": True}


@router.get("/blacklist")
def blacklist_export(since: int = 0, c=Depends(get_conn)):
    """增量黑名单，条目列表带主站签名。小站验不过签名就不收。"""
    return blacklist.export_since(c, since)


class BanReq(BaseModel):
    q: str = ""
    uid: Optional[int] = None
    reason: str = ""


def _resolve_user(c, p: BanReq):
    """认用户名 / @标识 / 昵称 / UID。管理员手输的东西别太挑剔。"""
    if p.uid:
        u = c.execute("SELECT * FROM users WHERE id=? OR uid=?", (p.uid, p.uid)).fetchone()
        if u:
            return u
    raw = (p.q or "").strip().lstrip("@")
    if not raw:
        return None
    u = c.execute("SELECT * FROM users WHERE name=? OR handle=?", (raw, raw.lower())).fetchone()
    if u:
        return u
    if raw.isdigit():
        u = c.execute("SELECT * FROM users WHERE uid=? OR id=?", (int(raw), int(raw))).fetchone()
        if u:
            return u
    rows = c.execute("SELECT * FROM users WHERE nickname=?", (raw,)).fetchall()
    return rows[0] if len(rows) == 1 else None


def _ban_target(u):
    """黑名单里的 uid 一律用本机主键；主站主键就是全网权威 id。"""
    return int(u["master_uid"] or u["id"])


@router.post("/admin/ban")
def admin_ban(p: BanReq, c=Depends(get_conn), user=Depends(require_user)):
    """封号。写库即可，小站 60 秒内自己拉到。"""
    _need_admin(user)
    u = _resolve_user(c, p)
    if not u:
        raise HTTPException(404, "没这个人")
    if u["is_admin"]:
        raise HTTPException(400, "不能封管理员")
    ts = blacklist.ban(c, _ban_target(u), p.reason.strip()[:200])
    return {"ok": True, "uid": _ban_target(u), "ts": ts, "user": user_json(u)}


@router.post("/admin/unban")
def admin_unban(p: BanReq, c=Depends(get_conn), user=Depends(require_user)):
    _need_admin(user)
    u = _resolve_user(c, p)
    if not u:
        raise HTTPException(404, "没这个人")
    blacklist.unban(c, _ban_target(u))
    return {"ok": True, "uid": _ban_target(u)}


@router.get("/admin/blacklist")
def admin_blacklist(c=Depends(get_conn), user=Depends(require_user)):
    _need_admin(user)
    rows = c.execute(
        "SELECT b.uid, b.ts, b.reason, b.synced_at, u.name, u.nickname "
        "FROM blacklist b LEFT JOIN users u ON u.id=b.uid ORDER BY b.ts DESC LIMIT 500").fetchall()
    return {
        "items": [{"uid": r["uid"], "ts": r["ts"], "reason": r["reason"] or "",
                   "name": r["name"] or "", "nickname": r["nickname"] or "",
                   "synced_at": r["synced_at"] or 0} for r in rows],
        "status": blacklist.status(),
    }


@router.delete("/friends/{uid}")
def friend_del(uid: int, c=Depends(get_conn), user=Depends(require_user)):
    """从名单上拿下来，不删账号。"""
    _need_admin(user)
    c.execute("DELETE FROM friends WHERE user_id=?", (uid,))
    c.commit()
    return {"ok": True}
