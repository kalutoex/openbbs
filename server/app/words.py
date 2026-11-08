# -*- coding: utf-8 -*-
"""敏感词表与图片黑名单。

词表是纯文件，站长直接编辑，改完 60 秒内（其实是下次 check 时看 mtime）生效，不用重启。
两个进程（IPv4 / IPv6 各一个实例）各看各的，不做进程间同步 —— 文件是唯一真相。
"""
import hashlib
import os
import re
import time

from . import config

WORDS_FILE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                          "config", "sensitive.txt")
IMAGE_BLOCK_FILE = os.path.join(config.path("data"), "image_block.txt")

TEMPLATE = """# 一行一个词，# 开头是注释，空行忽略。
# 匹配是「包含」匹配：正文/标题/昵称里出现这个词就拦。
# 英文不分大小写，中文照字面比。
# 改完保存即可，服务端下次检查时自动重新加载。
"""

# (mtime, 词表, 编译好的正则)
_cache = [0.0, [], None]


def _load():
    """返回编译好的正则；没有词表返回 None。"""
    try:
        mtime = os.path.getmtime(WORDS_FILE)
    except OSError:
        # 文件被删了：当空表，别拿旧缓存继续拦人
        _cache[:] = [0.0, [], None]
        return None
    if mtime == _cache[0]:
        return _cache[2]
    words = []
    try:
        with open(WORDS_FILE, encoding="utf-8") as f:
            for line in f:
                w = line.strip()
                if not w or w.startswith("#"):
                    continue
                words.append(w)
    except OSError:
        words = []
    rx = None
    if words:
        # 词多也不用 Aho-Corasick：几千条以内的正则在 Python 里够快，
        # 而且 re 的 C 引擎比手写 trie 稳。
        rx = re.compile("|".join(map(re.escape, words)), re.IGNORECASE)
    _cache[:] = [mtime, words, rx]
    return rx


def ensure_file():
    """首次启动时把模板写出来，站长打开就能加词。"""
    if os.path.exists(WORDS_FILE):
        return
    os.makedirs(os.path.dirname(WORDS_FILE), exist_ok=True)
    try:
        with open(WORDS_FILE, "w", encoding="utf-8") as f:
            f.write(TEMPLATE)
    except OSError:
        pass


def check(texts):
    """texts 是若干段文本。命中就在检查处 raise，所以这里只返回那个词；没命中返回 ''。"""
    rx = _load()
    if rx is None:
        return ""
    for t in texts:
        if not t:
            continue
        m = rx.search(str(t))
        if m:
            return m.group(0)
    return ""


def words():
    _load()
    return list(_cache[1])


# ---------------------------------------------------------------- 图片黑名单


def _hashes():
    try:
        with open(IMAGE_BLOCK_FILE, encoding="utf-8") as f:
            return {ln.strip().lower() for ln in f if re.fullmatch(r"[0-9a-fA-F]{64}", ln.strip())}
    except OSError:
        return set()


def blocked_image(digest):
    return digest.lower() in _hashes()


def block_image(digest):
    digest = digest.lower()
    hs = _hashes()
    if digest in hs:
        return False
    os.makedirs(os.path.dirname(IMAGE_BLOCK_FILE), exist_ok=True)
    with open(IMAGE_BLOCK_FILE, "a", encoding="utf-8") as f:
        f.write(digest + "\n")
    return True


def unblock_image(digest):
    digest = digest.lower()
    hs = _hashes()
    if digest not in hs:
        return False
    hs.discard(digest)
    tmp = IMAGE_BLOCK_FILE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        for h in sorted(hs):
            f.write(h + "\n")
    os.replace(tmp, IMAGE_BLOCK_FILE)
    return True


def blocked_list():
    return sorted(_hashes())


def digest_of_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()
