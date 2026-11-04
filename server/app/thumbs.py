# -*- coding: utf-8 -*-
"""缩略图：/img/t/<目标宽度>/<原图相对路径>

feed 里一屏的图，没必要每张都传整图。目标宽度定下来就切一张存盘，之后一直发这张。
动图（gif、动态 webp）原样转发——缩了就只剩一帧，不值当。

切图是懒加载的：第一次有人请求才做，做完写盘，后面全是静态文件。
两个请求同时要同一张也没事，各写各的临时文件，最后 rename 覆盖，结果一样。
"""
import os
import tempfile
import threading

from fastapi import HTTPException
from fastapi.responses import FileResponse

from . import config

# 客户端传多少都行，但只认这一段，免得有人拿它当任意尺寸的转码服务。
MIN_W, MAX_W = 48, 1600
QUALITY = 82

# 切图是纯 CPU 活，一次一张就够，多了只是在抢 GIL。
_build_lock = threading.Lock()

_CACHE = {"Cache-Control": "public, max-age=31536000, immutable"}


def _uploads_root():
    return os.path.realpath(config.path("uploads"))


def _src_path(rel):
    """把 URL 里的相对路径落到 uploads 里，越界的一律不认。"""
    root = _uploads_root()
    p = os.path.realpath(os.path.join(root, rel))
    if p != root and not p.startswith(root + os.sep):
        return None
    return p


def _dst_path(rel, w):
    return os.path.join(config.path("thumbs"), str(w),
                        os.path.splitext(rel)[0] + ".webp")


def _animated(src, ext):
    if ext == ".gif":
        return True
    if ext == ".webp":
        from PIL import Image
        try:
            with Image.open(src) as im:
                return bool(getattr(im, "is_animated", False))
        except Exception:
            return False
    return False


def build(src, dst, w):
    """切一张存盘。失败返回 False，调用方退回原图。"""
    from PIL import Image, ImageOps
    try:
        with Image.open(src) as im:
            if getattr(im, "is_animated", False):
                im.seek(0)
            im = ImageOps.exif_transpose(im)
            if im.width > w:
                h = max(1, round(im.height * w / im.width))
                im = im.resize((w, h), Image.BILINEAR)
            if im.mode not in ("RGB", "RGBA"):
                im = im.convert("RGBA" if "A" in im.mode or im.mode == "P" else "RGB")
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            fd, tmp = tempfile.mkstemp(dir=os.path.dirname(dst), suffix=".tmp")
            os.close(fd)
            try:
                im.save(tmp, "WEBP", quality=QUALITY, method=4)
                os.replace(tmp, dst)
            except Exception:
                if os.path.exists(tmp):
                    os.unlink(tmp)
                raise
        return True
    except Exception:
        return False


def thumb(w: int, path: str):
    src = _src_path(path)
    if not src or not os.path.isfile(src):
        raise HTTPException(404)
    if w < MIN_W:
        w = MIN_W
    elif w > MAX_W:
        w = MAX_W

    ext = os.path.splitext(src)[1].lower()
    if ext in (".gif", ".svg"):
        return FileResponse(src, headers=_CACHE)

    dst = _dst_path(path, w)
    try:
        fresh = os.path.getmtime(dst) >= os.path.getmtime(src)
    except OSError:
        fresh = False

    if not fresh:
        with _build_lock:
            try:
                fresh = os.path.getmtime(dst) >= os.path.getmtime(src)
            except OSError:
                fresh = False
            if not fresh:
                # 动图不缩，缩了就不动了。
                if _animated(src, ext) or not build(src, dst, w):
                    return FileResponse(src, headers=_CACHE)

    return FileResponse(dst, media_type="image/webp", headers=_CACHE)
