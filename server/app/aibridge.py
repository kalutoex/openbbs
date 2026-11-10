# -*- coding: utf-8 -*-
"""AI 接入：让一个 OneBot v11 实现（AstrBot 等）替人驱动账号。

方向是**反向 WS**——本服务主动连出去，对方是服务端。这样 AstrBot 那边
一行代码都不用改，用内置的 aiocqhttp 适配器就能接上，插件生态照旧。

多进程是这里最要紧的一件事。库被好几个 uvicorn 进程共享（IPv4、IPv6、
明文、TLS 各起一个），桥只能有一个在跑，否则同一条私信会被答五遍。
所以用文件锁选主：抢到锁的那个进程跑桥，其余进程只往 ai_outbox 写。

跨进程投递也走库。ai_outbox 是幂等的，leader 每半秒拉一遍没发过的，
推完标记 sent_at——请求路由到哪个进程都无所谓。
"""

import asyncio
import fcntl
import json
import os
import sqlite3
import time
import uuid
from typing import Any, Awaitable, Callable

from websockets.asyncio.client import connect

from . import db

LOCK_PATH = os.path.join(os.path.dirname(db.DB), "ai_bridge.lock")

# 事件推不出去时留着重试多久。超过这个岁数就丢掉，别让库一直涨。
OUTBOX_TTL = 7 * 24 * 3600

# 一轮最多捞多少条待发事件。
OUTBOX_BATCH = 50

# 从 OpenBBS 发给 AI 的，统一是这个「动作」的外壳。
# AstrBot 只认真实事件字段，多的字段它会忽略，所以带上 openbbs 的上下文是安全的。
_META = None


def _conn() -> sqlite3.Connection:
    c = sqlite3.connect(db.DB, timeout=10)
    c.row_factory = sqlite3.Row
    return c


def _try_lock() -> int | None:
    """抢桥的独占权。抢不到返回 None。"""
    os.makedirs(os.path.dirname(LOCK_PATH), exist_ok=True)
    fd = os.open(LOCK_PATH, os.O_RDWR | os.O_CREAT, 0o644)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        return fd
    except OSError:
        os.close(fd)
        return None


# ---------------------------------------------------------------- 写侧
# 这两个函数任何进程都能调，只写库，不碰连接。


def enqueue(uid: int, kind: str, payload: dict) -> None:
    """给某个 AI 账号投一条事件。uid 没开 AI 就直接忽略。"""
    try:
        c = _conn()
        try:
            row = c.execute("SELECT ai_enabled FROM users WHERE id=?", (uid,)).fetchone()
            if not row or not row["ai_enabled"]:
                return
            c.execute(
                "INSERT INTO ai_outbox(uid, kind, payload, created_at) VALUES(?,?,?,?)",
                (uid, kind, json.dumps(payload, ensure_ascii=False), int(time.time())),
            )
            c.commit()
        finally:
            c.close()
    except Exception as e:  # noqa: BLE001
        print("[ai] 投递失败 uid=%s %r" % (uid, e), flush=True)


def enqueue_dm(to_uid: int, from_uid: int, from_name: str, body: str,
               images: list | None, msg_id: int) -> None:
    """有人给 AI 账号发私信。"""
    enqueue(to_uid, "dm", {
        "from_uid": from_uid,
        "from_name": from_name,
        "body": body,
        "images": images or [],
        "msg_id": msg_id,
    })


def enqueue_comment(ai_uid: int, from_uid: int, from_name: str, body: str,
                    thread_id: int, thread_title: str, reply_id: int) -> None:
    """互关的人在 AI 账号的帖子下面评论了。"""
    enqueue(ai_uid, "comment", {
        "from_uid": from_uid,
        "from_name": from_name,
        "body": body,
        "thread_id": thread_id,
        "thread_title": thread_title,
        "reply_id": reply_id,
    })


# ---------------------------------------------------------------- 回调
# 发消息时桥不直接写库，交给 api 注入的处理函数，避免循环 import。

SendHandler = Callable[[int, int, str, list, str], Awaitable[dict]]
"""(自 uid, 对方 uid, 正文, 图片, 来源) -> {"message_id": n}"""


class _Bridge:
    def __init__(self) -> None:
        self._clients: dict[int, "_Client"] = {}
        self._fd: int | None = None
        self._task: asyncio.Task | None = None
        self._send_handler: SendHandler | None = None
        # 私信里刚回过的上下文（评论触发时，要把下一句写成楼层）
        self._pending: dict[int, dict] = {}

    # ---- 生命周期

    def set_send_handler(self, fn: SendHandler) -> None:
        self._send_handler = fn

    def is_leader(self) -> bool:
        return self._fd is not None

    def start(self) -> bool:
        """启动。抢不到锁就静默退出，返回 False。"""
        if self._task is not None:
            return True
        self._fd = _try_lock()
        if self._fd is None:
            return False
        self._task = asyncio.create_task(self._supervise())
        print("[ai] 桥已接管（pid %d）" % os.getpid(), flush=True)
        return True

    async def stop(self) -> None:
        for c in list(self._clients.values()):
            c.stop()
        self._clients.clear()
        if self._task:
            self._task.cancel()
            try:
                await self._task
            except asyncio.CancelledError:
                pass
            self._task = None
        if self._fd is not None:
            try:
                fcntl.flock(self._fd, fcntl.LOCK_UN)
                os.close(self._fd)
            except OSError:
                pass
            self._fd = None

    # ---- 主循环

    async def _supervise(self) -> None:
        while True:
            try:
                await self._sync_clients()
                await self._drain_outbox()
                await self._gc()
            except asyncio.CancelledError:
                raise
            except Exception as e:  # noqa: BLE001
                print("[ai] 主循环出错：%r" % (e,), flush=True)
            await asyncio.sleep(0.5)

    async def _sync_clients(self) -> None:
        """按库里的配置增删连接。配置改了不用重启，最多半秒生效。"""
        rows = await asyncio.to_thread(
            lambda: _conn().execute(
                "SELECT id, name, ai_ws, ai_token FROM users "
                "WHERE ai_enabled=1 AND ai_ws IS NOT NULL AND ai_ws != ''"
            ).fetchall()
        )
        want = {}
        for r in rows:
            want[r["id"]] = (r["ai_ws"], r["ai_token"] or "", r["name"])

        for uid in list(self._clients):
            if uid not in want:
                self._clients[uid].stop()
                del self._clients[uid]

        for uid, (url, token, name) in want.items():
            cur = self._clients.get(uid)
            if cur is None:
                c = _Client(self, uid, name, url, token)
                self._clients[uid] = c
                c.start()
            elif (cur.url, cur.token) != (url, token):
                # 地址或令牌换了，重连
                cur.stop()
                c = _Client(self, uid, name, url, token)
                self._clients[uid] = c
                c.start()

    async def _drain_outbox(self) -> None:
        if not self._clients:
            return
        rows = await asyncio.to_thread(_fetch_pending)
        for r in rows:
            c = self._clients.get(r["uid"])
            if c is None or not c.connected:
                continue
            ev = self._render(r)
            if ev is None:
                await asyncio.to_thread(_mark_sent, r["id"])
                continue
            ok = await c.push(ev)
            if ok:
                await asyncio.to_thread(_mark_sent, r["id"])
            else:
                break  # 这条推不动，下一轮再说，别堵后面的

    def _render(self, row) -> dict | None:
        """把 outbox 的一行翻成 OneBot 私聊消息事件。"""
        p = json.loads(row["payload"])
        uid = row["uid"]
        now = int(time.time())
        if row["kind"] == "dm":
            text = p["body"] or ""
            if not text and p.get("images"):
                text = "[图片]"
            ev = {
                "time": now,
                "self_id": uid,
                "post_type": "message",
                "message_type": "private",
                "sub_type": "friend",
                "message_id": p["msg_id"],
                "user_id": p["from_uid"],
                "message": [{"type": "text", "data": {"text": text}}],
                "raw_message": text,
                "font": 0,
                "sender": {"user_id": p["from_uid"], "nickname": p["from_name"], "card": ""},
            }
            # 记一下：这个人在私聊里问过她，后面的回复走私信
            self._pending[(uid, p["from_uid"])] = {"kind": "dm"}
            return ev

        if row["kind"] == "comment":
            # 评论也走私聊事件，正文里把上下文写清楚。
            # OneBot 里没有「评论」这种东西，硬造事件类型 AstrBot 不认，
            # 写成一条带出处的私聊，模型反而看得懂该回什么。
            text = (
                "（%s 在帖子《%s》下评论：%s）"
                % (p["from_name"], p["thread_title"], p["body"])
            )
            ev = {
                "time": now,
                "self_id": uid,
                "post_type": "message",
                "message_type": "private",
                "sub_type": "friend",
                "message_id": 900000000 + int(row["id"]),
                "user_id": p["from_uid"],
                "message": [{"type": "text", "data": {"text": text}}],
                "raw_message": text,
                "font": 0,
                "sender": {"user_id": p["from_uid"], "nickname": p["from_name"], "card": ""},
            }
            self._pending[(uid, p["from_uid"])] = {
                "kind": "comment",
                "thread_id": p["thread_id"],
                "reply_id": p["reply_id"],
            }
            return ev
        return None

    async def _gc(self) -> None:
        if int(time.time()) % 60 > 1:
            return
        await asyncio.to_thread(_purge_old)


def _fetch_pending():
    c = _conn()
    try:
        return c.execute(
            "SELECT * FROM ai_outbox WHERE sent_at IS NULL ORDER BY id LIMIT ?",
            (OUTBOX_BATCH,),
        ).fetchall()
    finally:
        c.close()


def _mark_sent(row_id: int) -> None:
    c = _conn()
    try:
        c.execute("UPDATE ai_outbox SET sent_at=? WHERE id=?", (int(time.time()), row_id))
        c.commit()
    finally:
        c.close()


def _purge_old() -> None:
    c = _conn()
    try:
        c.execute("DELETE FROM ai_outbox WHERE created_at < ?",
                  (int(time.time()) - OUTBOX_TTL,))
        c.commit()
    finally:
        c.close()


# ---------------------------------------------------------------- 单条连接


class _Client:
    def __init__(self, bridge: _Bridge, uid: int, name: str, url: str, token: str) -> None:
        self.bridge = bridge
        self.uid = uid
        self.name = name
        self.url = url
        self.token = token
        self.ws = None
        self.connected = False
        self._stopped = False
        self._task: asyncio.Task | None = None
        self._hb: asyncio.Task | None = None
        self._seq = 0

    def start(self) -> None:
        self._task = asyncio.create_task(self._run())

    def stop(self) -> None:
        self._stopped = True
        if self._hb:
            self._hb.cancel()
        if self._task:
            self._task.cancel()

    def _headers(self) -> dict:
        h = {"User-Agent": "OpenBBS-OneBot/1.0"}
        if self.token:
            h["Authorization"] = "Bearer " + self.token
        return h

    async def _run(self) -> None:
        backoff = 1.0
        while not self._stopped:
            try:
                async with connect(
                    self.url,
                    additional_headers=self._headers(),
                    open_timeout=10,
                    ping_interval=None,   # 心跳自己发，OneBot 侧看得懂
                    max_size=4 * 1024 * 1024,
                ) as ws:
                    self.ws = ws
                    self.connected = True
                    backoff = 1.0
                    await self._on_open(ws)
                    await self._read_loop(ws)
            except asyncio.CancelledError:
                raise
            except Exception as e:  # noqa: BLE001
                self._report_error(e)
            finally:
                self.connected = False
                self.ws = None
                if self._hb:
                    self._hb.cancel()
                    self._hb = None
            if self._stopped:
                break
            await asyncio.sleep(backoff)
            backoff = min(backoff * 2, 30.0)

    async def _on_open(self, ws) -> None:
        await asyncio.to_thread(_mark_seen, self.uid)
        await self._send_json({
            "time": int(time.time()),
            "self_id": self.uid,
            "post_type": "meta_event",
            "meta_event_type": "lifecycle",
            "sub_type": "connect",
        })
        self._hb = asyncio.create_task(self._heartbeat())

    async def _heartbeat(self) -> None:
        while True:
            await asyncio.sleep(25)
            await self._send_json({
                "time": int(time.time()),
                "self_id": self.uid,
                "post_type": "meta_event",
                "meta_event_type": "heartbeat",
                "status": {"online": True, "good": True},
                "interval": 25000,
            })

    async def _send_json(self, obj: dict) -> bool:
        ws = self.ws
        if ws is None:
            return False
        try:
            await ws.send(json.dumps(obj, ensure_ascii=False))
            return True
        except Exception:
            return False

    async def push(self, event: dict) -> bool:
        return await self._send_json(event)

    async def _read_loop(self, ws) -> None:
        async for raw in ws:
            if isinstance(raw, bytes):
                continue
            try:
                msg = json.loads(raw)
            except Exception:
                continue
            # 带 echo 的是 API 调用；没有的是对方的事件（我们不用）
            if "echo" in msg:
                asyncio.create_task(self._handle_api(ws, msg))

    async def _handle_api(self, ws, msg: dict) -> None:
        action = msg.get("action") or ""
        params = msg.get("params") or {}
        echo = msg.get("echo")
        try:
            data = await self._call(action, params)
            res = {"status": "ok", "retcode": 0, "data": data, "echo": echo,
                   "message": "", "wording": ""}
        except _ApiError as e:
            res = {"status": "failed", "retcode": e.code, "data": None,
                   "echo": echo, "message": str(e), "wording": str(e)}
        except Exception as e:  # noqa: BLE001
            res = {"status": "failed", "retcode": 200, "data": None,
                   "echo": echo, "message": repr(e), "wording": repr(e)}
        try:
            await ws.send(json.dumps(res, ensure_ascii=False))
        except Exception:
            pass

    async def _call(self, action: str, p: dict) -> Any:
        if action in ("send_private_msg", "send_msg"):
            text, images = _segments_to_text(p.get("message"))
            target = p.get("user_id")
            if action == "send_msg" and p.get("message_type") == "group":
                raise _ApiError(1404, "这里没有群")
            if not target:
                raise _ApiError(1400, "缺 user_id")
            text = text.strip()
            if not text and not images:
                raise _ApiError(1400, "空消息")
            if self.bridge._send_handler is None:
                raise _ApiError(1403, "桥还没挂上发送器")
            # 上一轮是评论触发的话，这句就该写成楼层而不是私信
            pending = self.bridge._pending.pop((self.uid, int(target)), None)
            source = "comment" if pending and pending.get("kind") == "comment" else "dm"
            ctx = pending if source == "comment" else {}
            out = await self.bridge._send_handler(
                self.uid, int(target), text, images, source, ctx
            )
            return {"message_id": out.get("message_id", 0)}

        if action == "get_login_info":
            return {"user_id": self.uid, "nickname": self.name}

        if action == "get_friend_list":
            return await asyncio.to_thread(_friend_list, self.uid)

        if action == "get_stranger_info":
            return await asyncio.to_thread(_stranger_info, int(p.get("user_id") or 0))

        if action == "get_version_info":
            return {"app_name": "OpenBBS", "app_version": "1.0", "protocol_version": "v11"}

        if action == "get_status":
            return {"online": True, "good": True}

        if action == "can_send_image":
            return {"yes": False}

        if action == "can_send_record":
            return {"yes": False}

        if action in ("set_restart", "clean_cache"):
            return {}

        raise _ApiError(1404, "不支持的动作：%s" % action)

    def _report_error(self, e: Exception) -> None:
        msg = str(e)[:180] or e.__class__.__name__
        try:
            asyncio.create_task(asyncio.to_thread(_mark_error, self.uid, msg))
        except Exception:
            pass


class _ApiError(Exception):
    def __init__(self, code: int, msg: str) -> None:
        super().__init__(msg)
        self.code = code


def _segments_to_text(message) -> tuple[str, list]:
    """OneBot 消息段 -> 纯文本 + 图片地址。"""
    if message is None:
        return "", []
    if isinstance(message, str):
        return message, []
    parts, images = [], []
    for seg in message:
        if not isinstance(seg, dict):
            continue
        t = seg.get("type")
        d = seg.get("data") or {}
        if t == "text":
            parts.append(str(d.get("text") or ""))
        elif t == "image":
            url = d.get("url") or d.get("file") or ""
            if url:
                images.append(url)
        elif t == "at":
            parts.append("@" + str(d.get("qq") or ""))
        elif t == "face":
            parts.append("[表情]")
        # reply / record / video / json / forward 一律不展开，第一版只收文字
    return "".join(parts), images


def _mark_seen(uid: int) -> None:
    c = _conn()
    try:
        c.execute("UPDATE users SET ai_seen_at=?, ai_error=NULL WHERE id=?",
                  (int(time.time()), uid))
        c.commit()
    finally:
        c.close()


def _mark_error(uid: int, msg: str) -> None:
    c = _conn()
    try:
        c.execute("UPDATE users SET ai_error=? WHERE id=?", (msg, uid))
        c.commit()
    finally:
        c.close()


def _friend_list(uid: int) -> list:
    c = _conn()
    try:
        rows = c.execute(
            "SELECT u.id, u.name, COALESCE(u.nickname,u.name) AS nick FROM users u "
            "WHERE EXISTS(SELECT 1 FROM follows f WHERE f.follower_id=? AND f.target_id=u.id) "
            "AND EXISTS(SELECT 1 FROM follows g WHERE g.follower_id=u.id AND g.target_id=?)",
            (uid, uid),
        ).fetchall()
        return [{"user_id": r["id"], "nickname": r["nick"],
                 "remark": "", "sex": "unknown", "age": 0} for r in rows]
    finally:
        c.close()


def _stranger_info(uid: int) -> dict:
    c = _conn()
    try:
        r = c.execute("SELECT id, name, COALESCE(nickname,name) AS nick FROM users WHERE id=?",
                      (uid,)).fetchone()
        if not r:
            raise _ApiError(1404, "没这个人")
        return {"user_id": r["id"], "nickname": r["nick"], "sex": "unknown", "age": 0}
    finally:
        c.close()


bridge = _Bridge()
