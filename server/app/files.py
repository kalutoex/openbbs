# -*- coding: utf-8 -*-
"""附件的存盘逻辑。只管字节和路径，不碰路由和权限。

存 content-addressed：data/files/<sha 前2位>/<sha 前20位>，没有扩展名。
文件名、大小、上传者都在 files 表里，下载时按表里的名字给 Content-Disposition。
所以同一个包发十次也只占一份空间。

大文件不能整块读进内存：边收边算 sha256，收完才决定要不要 rename 到位。
超限就在中途掐掉，临时文件删干净。
"""
import hashlib
import mimetypes
import os
import tempfile

from . import config

MAX_MB = int(config.get("limits", "file_mb", 500) or 500)
MAX_BYTES = MAX_MB * 1024 * 1024
MAX_FILES = int(config.get("limits", "files_per_post", 5) or 5)
PER_DAY = int(config.get("limits", "files_per_day", 10) or 10)
PER_DAY_MB = int(config.get("limits", "files_mb_per_day", 3000) or 3000)

CHUNK = 1 << 20


def root():
    return config.path("files")


def path_of(digest):
    return os.path.join(root(), digest[:2], digest)


def clean_name(raw):
    """只留文件名本身：去掉路径、控制字符，长度掐到 120。"""
    name = os.path.basename(str(raw or "").replace("\\", "/")).strip()
    name = "".join(ch for ch in name if ch.isprintable() and ch not in "\r\n\t")
    if not name:
        name = "file"
    if len(name) > 120:
        stem, ext = os.path.splitext(name)
        name = stem[: 120 - len(ext)] + ext
    return name


def guess_mime(name):
    return mimetypes.guess_type(name)[0] or "application/octet-stream"


class TooBig(Exception):
    pass


class Empty(Exception):
    pass


async def ingest(upload, limit):
    """把上传流写到临时文件，返回 (digest, size, path)。"""
    os.makedirs(root(), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=root(), suffix=".part")
    h = hashlib.sha256()
    size = 0
    try:
        with os.fdopen(fd, "wb") as out:
            while True:
                chunk = await upload.read(CHUNK)
                if not chunk:
                    break
                size += len(chunk)
                if size > limit:
                    raise TooBig()
                h.update(chunk)
                out.write(chunk)
        if size == 0:
            raise Empty()
        digest = h.hexdigest()[:20]
        dst = path_of(digest)
        if os.path.exists(dst):
            # 内容已经有了，白收一遍，直接扔掉临时文件。
            os.unlink(tmp)
            tmp = None
        else:
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            os.replace(tmp, dst)
            tmp = None
        return digest, size, dst
    finally:
        if tmp and os.path.exists(tmp):
            os.unlink(tmp)


def quota(c, user_id, since):
    """今天的用量：(个数, 字节)。"""
    row = c.execute(
        "SELECT COUNT(*) AS n, COALESCE(SUM(size),0) AS s FROM files "
        "WHERE uploader=? AND created_at>=?", (user_id, since)).fetchone()
    return row["n"], row["s"]
