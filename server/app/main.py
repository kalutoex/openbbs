# -*- coding: utf-8 -*-
"""论坛主程序。服务端渲染，不依赖 Node。"""
import asyncio, math, os, time
from fastapi import FastAPI, Request, Form, Depends, HTTPException
from fastapi.responses import HTMLResponse, JSONResponse, RedirectResponse, FileResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates

from . import api, auth, blacklist, config, db, files as filesvc, sites, thumbs

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
_IMMUTABLE_PREFIX = ("/assets/", "/canvaskit/")
_IMMUTABLE_FILE = set()

from fastapi.middleware.cors import CORSMiddleware

# 跨源放行名单写在配置里（http.cors_origins）。
# 网页和接口同域名不同端口算跨源，不放行的话页面调不动接口。
app.add_middleware(
    CORSMiddleware,
    allow_origins=config.get("http", "cors_origins") or [],
    allow_origin_regex=config.get("http", "cors_origin_regex") or None,
    allow_methods=["*"],
    allow_headers=["*"],
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


@app.middleware("http")
async def cache_headers(request: Request, call_next):
    resp = await call_next(request)
    path = request.url.path
    if path in _NOCACHE:
        resp.headers["Cache-Control"] = "no-cache, must-revalidate"
    elif path == "/.well-known/bbs.json":
        # 站点自述变动不频繁，给客户端 5 分钟缓存，避免每次进站都问。
        resp.headers["Cache-Control"] = "public, max-age=300"
    elif path in _IMMUTABLE_FILE or path.startswith(_IMMUTABLE_PREFIX):
        resp.headers["Cache-Control"] = "public, max-age=31536000, immutable"
    elif path.startswith("/img/"):
        resp.headers["Cache-Control"] = "public, max-age=2592000"
    return resp


def ts(v):
    return time.strftime("%Y-%m-%d %H:%M", time.localtime(v))


tpl.env.filters["ts"] = ts
db.init()
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
    uid = auth.read_token(tok) if tok else None
    if not uid:
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
    row = c.execute("SELECT * FROM users WHERE name=?", (name.strip(),)).fetchone()
    if not row or not auth.check_pw(password, row["pw"]):
        return tpl.TemplateResponse(request, "login.html",
                                    {"user": None, "err": "用户名或密码不对", "nxt": nxt, "name": name},
                                    status_code=400)
    resp = RedirectResponse(nxt or "/classic", status_code=303)
    resp.set_cookie("sid", auth.make_token(row["id"]), httponly=True, samesite="lax",
                    max_age=86400 * 30, path="/")
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
    cur = c.execute("INSERT INTO users(name, pw, created_at) VALUES(?,?,?)",
                    (name, auth.hash_pw(password), now))
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
            finally:
                c.close()
            if n:
                print("[cloud] 回收站清理 %d 条" % n, flush=True)
        except Exception as e:  # noqa: BLE001 清理失败也要继续下一轮
            print("[cloud] 回收站清理出错：%r" % (e,), flush=True)
        await asyncio.sleep(3600)


@app.on_event("startup")
async def _start_trash_loop():
    asyncio.create_task(_trash_loop())
