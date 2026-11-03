# -*- coding: utf-8 -*-
"""SQLite 在线快照 + 快照自检。

用法：
  db_snapshot.py <源库> <目标库>   复制一份（WAL 里没落盘的内容也带上）
  db_snapshot.py --check <库>      验一下快照能打开、核心表查得动

这台机器没装 sqlite3 命令行，所以单独放个脚本，给 forum_backup.sh 用。
"""
import sqlite3
import sys

CHECK_SQL = [
    "select count(*) from users",
    "select count(*) from threads",
    "select count(*) from replies",
]


def snapshot(src, dst):
    c = sqlite3.connect(src, timeout=15)
    o = sqlite3.connect(dst)
    try:
        with o:
            c.backup(o)
    finally:
        o.close()
        c.close()


def check(path):
    c = sqlite3.connect("file:%s?mode=ro" % path, uri=True, timeout=10)
    try:
        for sql in CHECK_SQL:
            c.execute(sql).fetchone()
    finally:
        c.close()


def main(argv):
    if len(argv) == 3 and argv[1] == "--check":
        check(argv[2])
        return 0
    if len(argv) == 3:
        snapshot(argv[1], argv[2])
        return 0
    sys.stderr.write("用法: db_snapshot.py <源库> <目标库> | db_snapshot.py --check <库>\n")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
