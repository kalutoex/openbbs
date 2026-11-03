# -*- coding: utf-8 -*-
"""论坛主程序。服务端渲染，不依赖 Node。"""
import math, os, time
from fastapi import FastAPI, Request, Form, Depends, HTTPException
from fastapi.responses import HTMLResponse, RedirectResponse, FileResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates

from . import db, auth, api

ROOT = "/vol1/1000/data/code/ongoing/bbs/server"
PER_PAGE = 20

app = FastAPI(title="bbs")
app.mount("/static", StaticFiles(directory=ROOT + "/static"), name="static")
# 上传目录同样可覆盖：测试实例写自己的 uploads_test，别往生产图库里丢东西。
UPLOADS = os.environ.get("BBS_UPLOADS", ROOT + "/data/uploads")
os.makedirs(UPLOADS, exist_ok=True)
app.mount("/img", StaticFiles(directory=UPLOADS), name="img")
os.makedirs(ROOT + "/data/apk", exist_ok=True)
app.mount("/apk", StaticFiles(directory=ROOT + "/data/apk"), name="apk")
tpl = Jinja2Templates(directory=ROOT + "/templates")


# 缓存策略：入口文件不缓存（发版立刻生效），带指纹的资源长缓存。
# Flutter 的 service worker 会自己管版本，但入口和 sw 本身必须每次回源。
_NOCACHE = {"/", "/index.html", "/flutter_service_worker.js", "/version.json",
            "/flutter_bootstrap.js", "/manifest.json", "/main.dart.js"}
_IMMUTABLE_PREFIX = ("/assets/", "/canvaskit/")
_IMMUTABLE_FILE = set()

from fastapi.middleware.cors import CORSMiddleware

# 网页端从 ipv6bbs:26016（直连）或 ipv4bbs:24016（frp 兜底）进来。
# 同域名不同端口，属跨源，接口得放行，否则跨端口进来的页面调不动接口。
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        # 2026-10-21 端口重排：IPv6 直连 26016，IPv4 走樱花 frp 24016
        "https://ipv6bbs.kalutoex.dpdns.org:26016",
        "https://ipv4bbs.kalutoex.dpdns.org:24016",
        "http://share.kalutoex.dpdns.org:8080",
    ],
    allow_origin_regex=r"http://(localhost|127\.0\.0\.1)(:\d+)?",
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/go", response_class=HTMLResponse)
def entry_page():
    # 兜底入口页：纯静态，不依赖 Flutter，任何端口都能开。
    return FileResponse(ROOT + "/web/go.html", media_type="text/html")



# share.kalutoex.dpdns.org 2026-11-01 下线：旧版 App 的 8080 明文入口。
# 11-02 DNS 记录已删、HOSTS 已移除；这里的分支留着防旧 DNS 缓存，无害。
# 只对这个 Host 做 301，局域网 IP:8080 照旧（阿尔说 8080 端口不关）。
_SHARE_HOST = "share.kalutoex.dpdns.org"
_SHARE_TARGET = "https://ipv6bbs.kalutoex.dpdns.org:26016"
_ACCESS_8080 = ROOT + "/logs/access-8080.log"


def _log_8080(request: Request):
    """只记 8080 进来的请求，用来判断还有没有人在走明文入口。"""
    port = (request.scope.get("server") or ("", 0))[1]
    if port != 8080:
        return
    try:
        ip = request.client.host if request.client else ""
        host = request.headers.get("host", "")
        ua = request.headers.get("user-agent", "")[:90]
        with open(_ACCESS_8080, "a", encoding="utf-8") as f:
            f.write("%s\t%s\t%s\t%s %s\t%s\n" % (
                time.strftime("%Y-%m-%d %H:%M:%S"), ip, host,
                request.method, request.url.path, ua))
    except Exception:
        pass


@app.middleware("http")
async def cache_headers(request: Request, call_next):
    _log_8080(request)
    host = (request.headers.get("host") or "").split(":")[0].lower()
    if host == _SHARE_HOST:
        target = _SHARE_TARGET + request.url.path
        if request.url.query:
            target += "?" + request.url.query
        return RedirectResponse(target, status_code=301)
    resp = await call_next(request)
    path = request.url.path
    if path in _NOCACHE:
        resp.headers["Cache-Control"] = "no-cache, must-revalidate"
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
app.mount("/", StaticFiles(directory=ROOT + "/web", html=True), name="web")
