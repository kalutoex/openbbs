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

# 0 = 不限。单文件上限可以放开，因为 ingest 是流式写盘的，多大都不进内存。
MAX_MB = int(config.get("limits", "file_mb", 0) or 0)
MAX_BYTES = MAX_MB * 1024 * 1024 if MAX_MB > 0 else 0
MAX_FILES = int(config.get("limits", "files_per_post", 5) or 5)
PER_DAY = int(config.get("limits", "files_per_day", 0) or 0)
PER_DAY_MB = int(config.get("limits", "files_mb_per_day", 0) or 0)

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
                if limit and size > limit:
                    # 带上实际收到的字节数，调用方好算差多少
                    raise TooBig(size)
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


# ---------------------------------------------------------------- 云盘额度

def quota_of(user):
    """这个人的总额度（字节）。None = 不限。

    个人列有值就用个人的（VIP 调的就是这个），否则用全局默认。
    """
    try:
        q = user["quota_bytes"]
    except (IndexError, KeyError):
        q = None
    if q:
        return int(q)
    mb = int(config.get("limits", "cloud_quota_mb", 5120) or 0)
    return mb * 1024 * 1024 if mb > 0 else None


def used(c, user_id):
    """已占用字节。回收站里的不算——删掉立刻还空间。"""
    row = c.execute(
        "SELECT COALESCE(SUM(size),0) AS s FROM user_files "
        "WHERE user_id=? AND deleted_at IS NULL", (user_id,)).fetchone()
    return int(row["s"])


def remaining(c, user):
    """还剩多少字节。None = 不限。"""
    q = quota_of(user)
    if not q:
        return None
    return max(0, int(q) - used(c, user["id"]))


def human(n):
    """1024 进制，给提示文案用。"""
    n = float(max(0, int(n or 0)))
    if n < 1024:
        return "%d B" % n
    for unit in ("KB", "MB", "GB", "TB"):
        n /= 1024.0
        if n < 1024 or unit == "TB":
            return "%.1f %s" % (n, unit)


def full_msg(need=0):
    """空间不足的提示。文案在 site.json 的 limits.cloud_full_msg 里改。"""
    tpl = config.get("limits", "cloud_full_msg", "空间不足，还差 {need}") \
        or "空间不足，还差 {need}"
    return str(tpl).replace("{need}", human(need))


def quota(c, user_id, since):
    """今天的用量：(个数, 字节)。"""
    row = c.execute(
        "SELECT COUNT(*) AS n, COALESCE(SUM(size),0) AS s FROM files "
        "WHERE uploader=? AND created_at>=?", (user_id, since)).fetchone()
    return row["n"], row["s"]
