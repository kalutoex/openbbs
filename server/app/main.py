# -*- coding: utf-8 -*-
"""论坛主程序。服务端渲染，不依赖 Node。"""
import asyncio, hashlib, math, os, sqlite3, time
from fastapi import FastAPI, Request, Form, Depends, HTTPException
from fastapi.responses import HTMLResponse, JSONResponse, RedirectResponse, FileResponse, Response
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates

from . import api, auth, blacklist, config, db, files as filesvc, sites, thumbs, words

ROOT = config.ROOT
PER_PAGE = config.get("limits", "per_page", 20)

config.ensure_dirs()

app = FastAPI(title=config.get("site", "name") or "OpenBBS")

# 网页前端（Flutter web）和静态资源都是可选的：只跑 API 的部署不该起不来。
_WEB_DIR = os.path.join(ROOT, "web")
STATIC_DIR = os.path.join(ROOT, "static")
TEMPLATE_DIR = os.path.join(ROOT, "templates")

app.mount("/static", StaticFiles(directory=STATIC_DIR, check_dir=False), name="static")
# 上传目录：容器里一般挂到外部卷，由 config 决定。
UPLOADS = config.path("uploads")
os.makedirs(UPLOADS, exist_ok=True)
# 缩略图得排在 mount 前面，否则 /img/t/... 会被静态目录先吃掉变 404。
app.add_api_route("/img/t/{w:int}/{path:path}", thumbs.thumb, methods=["GET"])
app.mount("/img", StaticFiles(directory=UPLOADS), name="img")
APK_DIR = config.path("apk")
os.makedirs(APK_DIR, exist_ok=True)
app.mount("/apk", StaticFiles(directory=APK_DIR), name="apk")
# 附件下载：和 /img 一样在根路径上，帖子里的地址才短。
app.add_api_route("/f/{digest}", api.serve_file, methods=["GET", "HEAD"])
tpl = Jinja2Templates(directory=TEMPLATE_DIR)


# 缓存策略：入口文件不缓存（发版立刻生效），带指纹的资源长缓存。
# Flutter 的 service worker 会自己管版本，但入口和 sw 本身必须每次回源。
_NOCACHE = {"/", "/index.html", "/flutter_service_worker.js", "/version.json",
            "/flutter_bootstrap.js", "/manifest.json", "/main.dart.js"}
# 带指纹（文件名里含 hash）的才配 immutable。Flutter 的 assets 和 canvaskit
# 文件名是固定的，之前按 immutable 发，一年内浏览器都不来问一句。结果发版换了
# 字体子集，新代码用到的图标在老字体里没有字形，界面上就是一块空白——网页端
# 「有的图标显示不出来」就是这么来的。这类一律 no-cache + ETag，命中就是 304。
_NOFPRINT_PREFIX = ("/assets/", "/canvaskit/")
_IMMUTABLE_PREFIX = ()
_IMMUTABLE_FILE = set()

from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware

# 跨源放行名单写在配置里（http.cors_origins）。
# 网页和接口同域名不同端口算跨源，不放行的话页面调不动接口。
# 站点自己的入口一律放行：网页版换入口（v6 直连 ↔ v4 中转）之后，
# 页面在 A 域、接口和图片在 B 域，不回跨源头的话浏览器会把回应整个挡掉，
# 表现是「接口全挂」「图片一片灰」。配的名单是额外加的，不是替代。
_CORS_SELF = []
for _e in (config.get("site", "endpoints") or []):
    _u = _e if isinstance(_e, str) else (_e or {}).get("url") if isinstance(_e, dict) else ""
    _u = str(_u or "").strip().rstrip("/")
    if _u and _u not in _CORS_SELF:
        _CORS_SELF.append(_u)
_b = str(config.get("site", "base_url") or "").strip().rstrip("/")
if _b and _b not in _CORS_SELF:
    _CORS_SELF.append(_b)

app.add_middleware(
    CORSMiddleware,
    allow_origins=_CORS_SELF + list(config.get("http", "cors_origins") or []),
    allow_origin_regex=config.get("http", "cors_origin_regex") or None,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 网页端的 main.dart.js 将近 4MB、canvaskit.wasm 7MB，不压缩传得太慢。
# 只在客户端接受 gzip 且内容超过 1KB 时才压，图片这类本来就不再压的跳过。
app.add_middleware(
    GZipMiddleware,
    minimum_size=1024,
    # 附件多半是已经压过的包，再 gzip 一遍纯费 CPU，还会把流式下载拖慢。
    exclude_content_types=(
        "application/grpc",
        "application/gzip",
        "application/x-gzip",
        "application/zip",
        "application/x-7z-compressed",
        "application/x-rar-compressed",
        "application/x-tar",
        "application/octet-stream",
        "application/vnd.android.package-archive",
        "application/pdf",
        "audio/*",
        "font/woff",
        "font/woff2",
        "image/*",
        "text/event-stream",
        "video/*",
    ),
)


@app.get("/", response_class=HTMLResponse)
def root_page():
    # 网页前端没部署时给个落点，免得一进来就是 404。
    idx = os.path.join(_WEB_DIR, "index.html")
    if os.path.exists(idx):
        return FileResponse(idx, media_type="text/html")
    return HTMLResponse(
        "<h1>OpenBBS</h1><p>接口正常，网页前端还没部署。</p>"
        "<p><a href=\"/go\">接口自检</a> · <a href=\"/meta\">站点信息</a></p>"
    )


@app.get("/go", response_class=HTMLResponse)
def entry_page():
    # 兜底入口页：纯静态，不依赖 Flutter，任何端口都能开。
    f = os.path.join(_WEB_DIR, "go.html")
    if not os.path.exists(f):
        f = os.path.join(STATIC_DIR, "go.html")
    if os.path.exists(f):
        return FileResponse(f, media_type="text/html")
    return HTMLResponse("<h1>OpenBBS</h1><p>接口正常，前端还没放上去。</p>")




@app.middleware("http")
async def body_limit(request: Request, call_next):
    # 图片是 base64 上来的，10MB 的图算上编码差不多 13.3MB；
    # 再大的请求体直接挡掉，别等它全读进内存。
    # 附件上传（/api/file）是流式落盘的，不读进内存，有多大收多大；
    # 单文件上限由云盘剩余空间决定，这里不拦。
    if request.url.path == "/api/file" and request.method == "POST":
        return await call_next(request)
    cl = request.headers.get("content-length", "")
    if cl.isdigit() and int(cl) > 16 * 1024 * 1024:
        return JSONResponse({"detail": "请求体太大"}, status_code=413)
    return await call_next(request)


# ---------------------------------------------------------------- 写请求幂等
#
# 客户端的写操作超时后不再重发（重发会变成发两条帖、上传两份）。根治靠这层：
# 每个写请求带一个客户端生成的 X-Request-Id，同一个人同一个 id 在 60 秒内
# 只真正执行一次，后面的重试直接拿第一次的响应回放。
#
# 上传（/api/file*）不掺和：它自己按 offset 续传，重复发是无害的，而且请求体
# 是流式的，缓冲它没意义。老网页的表单 POST 也带不了这个头，走原路。
IDEM_WINDOW = 60
_IDEM_SKIP = ("/api/file", "/api/upload")


def _idem_key(rid: str, auth: str) -> str:
    # 带上 Authorization：别人的 id 撞上来也读不到你的结果。
    return hashlib.sha256((rid + "|" + auth).encode()).hexdigest()[:32]


def _idem_claim(key: str) -> bool:
    """认领这个 id。True = 归我干；False = 已经有人干过或正在干。"""
    c = db.conn()
    try:
        now = int(time.time())
        c.execute("DELETE FROM idem WHERE created_at < ?", (now - IDEM_WINDOW,))
        try:
            c.execute("INSERT INTO idem(key, created_at, status) VALUES(?,?,0)", (key, now))
            c.commit()
            return True
        except sqlite3.IntegrityError:
            return False
    finally:
        c.close()


def _idem_get(key: str):
    c = db.conn()
    try:
        return c.execute("SELECT status, ctype, body FROM idem WHERE key=?", (key,)).fetchone()
    finally:
        c.close()


def _idem_finish(key: str, status: int, ctype: str, body: bytes):
    c = db.conn()
    try:
        c.execute("UPDATE idem SET status=?, ctype=?, body=? WHERE key=?",
                  (status, ctype, body, key))
        c.commit()
    finally:
        c.close()


def _idem_drop(key: str):
    # 服务端自己出错了（5xx）：别把这份错误缓存 60 秒，让人能重试。
    c = db.conn()
    try:
        c.execute("DELETE FROM idem WHERE key=?", (key,))
        c.commit()
    finally:
        c.close()


def _idem_replay(row):
    return Response(content=row["body"] or b"", status_code=row["status"],
                    media_type=row["ctype"] or "application/json")


@app.middleware("http")
async def idempotent(request: Request, call_next):
    rid = (request.headers.get("x-request-id") or "").strip()
    if (not rid or request.method not in ("POST", "PUT", "PATCH", "DELETE")
            or not 8 <= len(rid) <= 64
            or not all(ch.isalnum() or ch in "-_" for ch in rid)):
        return await call_next(request)
    path = request.url.path
    if any(path.startswith(p) for p in _IDEM_SKIP):
        return await call_next(request)

    key = _idem_key(rid, request.headers.get("authorization", ""))
    if not _idem_claim(key):
        # 有人在跑（或已经跑完）：等它的结果，别自己再来一遍。
        for _ in range(50):  # 最多 5 秒
            row = _idem_get(key)
            if row is None:
                break  # 那条记录被清掉了，那就自己干
            if row["status"]:
                return _idem_replay(row)
            await asyncio.sleep(0.1)
        else:
            # 认领了却一直没交卷，多半是那个进程死了。接管过来。
            _idem_drop(key)
            _idem_claim(key)

    resp = await call_next(request)
    if resp.status_code >= 500:
        _idem_drop(key)
        return resp
    body = b""
    async for chunk in resp.body_iterator:
        body += chunk.encode() if isinstance(chunk, str) else chunk
    ctype = resp.headers.get("content-type")
    _idem_finish(key, resp.status_code, ctype, body)
    headers = {k: v for k, v in resp.headers.items()
               if k.lower() not in ("content-length", "content-encoding", "content-type")}
    return Response(content=body, status_code=resp.status_code, headers=headers,
                    media_type=ctype)


@app.middleware("http")
async def cache_headers(request: Request, call_next):
    resp = await call_next(request)
    path = request.url.path
    if path in _NOCACHE:
        resp.headers["Cache-Control"] = "no-cache, must-revalidate"
    elif path == "/.well-known/bbs.json":
        # 站点自述变动不频繁，给客户端 5 分钟缓存，避免每次进站都问。
        resp.headers["Cache-Control"] = "public, max-age=300"
    elif path.startswith(_NOFPRINT_PREFIX):
        resp.headers["Cache-Control"] = "no-cache, must-revalidate"
    elif path in _IMMUTABLE_FILE or path.startswith(_IMMUTABLE_PREFIX):
        resp.headers["Cache-Control"] = "public, max-age=31536000, immutable"
    elif path.startswith("/img/"):
        resp.headers["Cache-Control"] = "public, max-age=2592000"
    return resp


# 预压缩：deploy_web.sh 会给 JS / WASM 各留一份 .gz，这里直接发压缩好的那份。
# 不这么做的话，每个新访客都让服务端现场压 4MB 的 JS 和 7MB 的 wasm，一次约一秒 CPU。
_GZ_TYPES = {".js": "application/javascript", ".wasm": "application/wasm"}


@app.middleware("http")
async def static_gz(request: Request, call_next):
    if request.method in ("GET", "HEAD") and "gzip" in request.headers.get("accept-encoding", ""):
        path = os.path.normpath(request.url.path)
        ext = os.path.splitext(path)[1]
        if ext in _GZ_TYPES:
            fp = os.path.join(_WEB_DIR, path.lstrip("/"))
            if os.path.isfile(fp + ".gz"):
                resp = FileResponse(fp + ".gz", media_type=_GZ_TYPES[ext])
                resp.headers["Content-Encoding"] = "gzip"
                resp.headers["Vary"] = "Accept-Encoding"
                resp.headers["Cache-Control"] = (
                    "public, max-age=31536000, immutable"
                    if path in _IMMUTABLE_FILE
                    or (path.startswith(_IMMUTABLE_PREFIX) and _IMMUTABLE_PREFIX)
                    else "no-cache, must-revalidate"
                )
                return resp
    return await call_next(request)


def ts(v):
    return time.strftime("%Y-%m-%d %H:%M", time.localtime(v))


tpl.env.filters["ts"] = ts
db.init()
words.ensure_file()
api.seed()
app.include_router(api.router)

# 小站才需要后台拉黑名单；主站直接读自己的表，这个函数会自己判断角色。
blacklist.start_puller()
# 小站没 site_id 就自己去主站登记，拿到后存库，/meta 立刻能报。
sites.start_registrar()


@app.get("/meta")
def root_meta():
    """根级别名：小站只需要填个域名，不该得记 /api 前缀。"""
    return api.site_meta()


@app.get("/.well-known/bbs.json")
def well_known():
    """站点自述。客户端拿到域名先读这里，再决定用不用。"""
    return sites.well_known()


def get_conn():
    c = db.conn()
    try:
        yield c
    finally:
        c.close()


def current_user(request: Request, c=Depends(get_conn)):
    tok = request.cookies.get("sid")
    claims = auth.read_claims(tok) if tok else None
    uid = claims["uid"] if claims else None
    if not uid:
        return None
    # 改过密码之后，旧 cookie 里的版本落后，按未登录处理。
    row = c.execute("SELECT pw_ver FROM users WHERE id=?", (uid,)).fetchone()
    if row is not None and int(row["pw_ver"] or 0) > int(claims.get("v") or 0):
        return None
    # 封号在网页版也算没登录：接口层挡住了，界面别留个能点的壳。
    if blacklist.is_banned(c, uid):
        return None
    return c.execute("SELECT id, name FROM users WHERE id=?", (uid,)).fetchone()


def need_login(user):
    if not user:
        return RedirectResponse("/login?nxt=/new", status_code=303)
    return None


@app.get("/classic", response_class=HTMLResponse)
def index(request: Request, p: int = 1, c=Depends(get_conn), user=Depends(current_user)):
    p = max(1, p)
    total = c.execute("SELECT COUNT(*) AS n FROM threads").fetchone()["n"]
    rows = c.execute(
        "SELECT t.id, t.title, t.created_at, t.reply_count, u.name "
        "FROM threads t JOIN users u ON u.id = t.user_id "
        "ORDER BY t.is_top DESC, (CASE WHEN t.is_top=1 THEN t.created_at ELSE 0 END) ASC, "
        "t.created_at DESC LIMIT ? OFFSET ?",
        (PER_PAGE, (p - 1) * PER_PAGE)).fetchall()
    pages = max(1, math.ceil(total / PER_PAGE))
    return tpl.TemplateResponse(request, "index.html",
                                {"user": user, "rows": rows, "page": p, "pages": pages, "total": total})


@app.get("/t/{tid}", response_class=HTMLResponse)
def thread(tid: int, request: Request, c=Depends(get_conn), user=Depends(current_user)):
    t = c.execute(
        "SELECT t.id, t.title, t.body, t.created_at, u.name "
        "FROM threads t JOIN users u ON u.id = t.user_id WHERE t.id=?", (tid,)).fetchone()
    if not t:
        raise HTTPException(404, "帖子不存在")
    rs = c.execute(
        "SELECT r.id, r.body, r.created_at, u.name "
        "FROM replies r JOIN users u ON u.id = r.user_id "
        "WHERE r.thread_id=? ORDER BY r.id", (tid,)).fetchall()
    return tpl.TemplateResponse(request, "thread.html", {"user": user, "t": t, "rs": rs})


@app.get("/new", response_class=HTMLResponse)
def new_get(request: Request, user=Depends(current_user)):
    r = need_login(user)
    if r:
        return r
    return tpl.TemplateResponse(request, "new.html", {"user": user, "err": "", "title": "", "body": ""})


@app.post("/new")
def new_post(request: Request, title: str = Form(""), body: str = Form(""),
             c=Depends(get_conn), user=Depends(current_user)):
    r = need_login(user)
    if r:
        return r
    title, body = title.strip()[:200], body.strip()[:20000]
    if not title or not body:
        return tpl.TemplateResponse(request, "new.html",
                                    {"user": user, "err": "标题和正文都要填", "title": title, "body": body},
                                    status_code=400)
    now = int(time.time())
    cur = c.execute("INSERT INTO threads(title, body, user_id, created_at, updated_at) VALUES(?,?,?,?,?)",
                    (title, body, user["id"], now, now))
    c.commit()
    return RedirectResponse("/t/%d" % cur.lastrowid, status_code=303)


@app.post("/t/{tid}/reply")
def reply(tid: int, request: Request, body: str = Form(""),
          c=Depends(get_conn), user=Depends(current_user)):
    r = need_login(user)
    if r:
        return r
    body = body.strip()[:20000]
    if body:
        now = int(time.time())
        c.execute("INSERT INTO replies(thread_id, body, user_id, created_at) VALUES(?,?,?,?)",
                  (tid, body, user["id"], now))
        c.execute("UPDATE threads SET reply_count = reply_count + 1, updated_at=? WHERE id=?", (now, tid))
        c.commit()
    return RedirectResponse("/t/%d" % tid, status_code=303)


@app.get("/login", response_class=HTMLResponse)
def login_get(request: Request, nxt: str = "/", user=Depends(current_user)):
    return tpl.TemplateResponse(request, "login.html", {"user": user, "err": "", "nxt": nxt, "name": ""})


@app.post("/login")
def login_post(request: Request, name: str = Form(""), password: str = Form(""), nxt: str = Form("/"),
               c=Depends(get_conn)):
    who = name.strip()
    row = c.execute(
        "SELECT * FROM users WHERE name=? OR (email IS NOT NULL AND lower(email)=lower(?))",
        (who, who)).fetchone()
    if not row or not auth.check_pw(password, row["pw"]):
        return tpl.TemplateResponse(request, "login.html",
                                    {"user": None, "err": "用户名或密码不对", "nxt": nxt, "name": name},
                                    status_code=400)
    resp = RedirectResponse(nxt or "/classic", status_code=303)
    resp.set_cookie("sid", auth.make_token(row["id"], row["pw_ver"] or 0), httponly=True,
                    samesite="lax", max_age=86400 * 30, path="/")
    return resp


@app.get("/register", response_class=HTMLResponse)
def register_get(request: Request, user=Depends(current_user)):
    return tpl.TemplateResponse(request, "register.html", {"user": user, "err": "", "name": ""})


@app.post("/register")
def register_post(request: Request, name: str = Form(""), password: str = Form(""),
                  c=Depends(get_conn)):
    name = name.strip()
    err = ""
    if not (2 <= len(name) <= 20):
        err = "用户名 2–20 个字符"
    elif len(password) < 8:
        err = "密码至少 8 位"
    elif c.execute("SELECT 1 FROM users WHERE name=?", (name,)).fetchone():
        err = "这个名字有人用了"
    if err:
        return tpl.TemplateResponse(request, "register.html",
                                    {"user": None, "err": err, "name": name}, status_code=400)
    now = int(time.time())
    cur = c.execute("INSERT INTO users(name, pw, created_at, hue) VALUES(?,?,?,?)",
                    (name, auth.hash_pw(password), now, db.random_hue(c)))
    c.commit()
    resp = RedirectResponse("/classic", status_code=303)
    resp.set_cookie("sid", auth.make_token(cur.lastrowid), httponly=True, samesite="lax",
                    max_age=86400 * 30, path="/")
    return resp


@app.get("/logout")
def logout():
    resp = RedirectResponse("/classic", status_code=303)
    resp.delete_cookie("sid", path="/")
    return resp


# ---- 最后再挂静态根：Flutter 网页版（电脑用）----
# mount 必须放在所有路由之后，否则会把 /api、/login 这些全吃掉。
# base href "/"，Flutter 用 hash 路由（#/t/5），不会和 /t/{tid} 冲突。
# 老的 Jinja 页面还在 /classic。
# 没放网页包也照样能起——只跑接口的部署不需要 web 目录。
if os.path.isdir(_WEB_DIR):
    app.mount("/", StaticFiles(directory=_WEB_DIR, html=True), name="web")


# ---------------------------------------------------------------- 回收站清理任务

async def _trash_loop():
    """每小时扫一遍回收站。整段兜住异常，别让一次清理把服务带下去。"""
    while True:
        try:
            c = db.conn()
            try:
                n = filesvc.purge_trash(c)
                try:
                    days = int(config.get("limits", "trash_days",
                                          config.get("limits", "cloud_trash_days", 7)) or 7)
                except (TypeError, ValueError):
                    days = 7
                n += db.purge_thread_trash(c, days)
            finally:
                c.close()
            if n:
                print("[cloud] 回收站清理 %d 条" % n, flush=True)
        except Exception as e:  # noqa: BLE001 清理失败也要继续下一轮
            print("[cloud] 回收站清理出错：%r" % (e,), flush=True)
        await asyncio.sleep(3600)


@app.on_event("startup")
async def _start_trash_loop():
    # 上次没传完的分片，留一天就够了。
    try:
        n = filesvc.sweep_parts()
        if n:
            print("[cloud] 清了 %d 个残片" % n, flush=True)
    except Exception as e:  # noqa: BLE001
        print("[cloud] 清残片出错：%r" % (e,), flush=True)
    asyncio.create_task(_trash_loop())
