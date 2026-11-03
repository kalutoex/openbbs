#!/usr/bin/env python3
"""把 lib/ 里写死的中文搬到 ARB。

表在 lib/l10n/messages.tsv，一行一条，TAB 分隔：

    原文<TAB>键名<TAB>英文

原文里的 `$e`、`$_maxImgs`、`${diff.inMinutes}` 都是占位符，
会按出现顺序换成 `{v1}`、`{v2}`，代码里则换成对应实参。

键名如果 ARB 里已经有了，以 ARB 现有的中文为准（表里的原文只用来定位）。

用法：
    python3 tool/l10n_migrate.py --check    # 只报进度，不动文件
    python3 tool/l10n_migrate.py            # 生成 ARB，然后替换代码
"""
import argparse
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIB = os.path.join(ROOT, "lib")
ARB_ZH = os.path.join(LIB, "l10n", "app_zh.arb")
ARB_EN = os.path.join(LIB, "l10n", "app_en.arb")
TABLE = os.path.join(LIB, "l10n", "messages.tsv")

# 占位符：$e、$_maxImgs、${任意表达式}
PH = re.compile(r"\$\{([^{}]*)\}|\$([A-Za-z_][A-Za-z0-9_]*)")
CJK = re.compile(r"[\u4e00-\u9fff]")
IMPORT = "import '../l10n/l10n.dart';"


def parse(src):
    """把原文拆成 (模板, 实参列表)。

    `$e` -> `{v1}`，`'${diff.inMinutes} 分钟前'` -> `'{v1} 分钟前'`。
    占位符按出现顺序编号，编号就是 ARB 里的名字。
    """
    args, i = [], 0

    def sub(m):
        nonlocal i
        i += 1
        args.append(m.group(1) if m.group(1) is not None else m.group(2))
        return "{" + f"v{i}" + "}"

    return PH.sub(sub, src), args


def load_table():
    rows = []
    with open(TABLE, encoding="utf-8") as f:
        for n, line in enumerate(f, 1):
            line = line.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) < 3:
                sys.exit(f"messages.tsv 第 {n} 行不足三列：{line!r}")
            rows.append((parts[0], parts[1], parts[2]))
    return rows


def dart_call(key, args):
    if not args:
        return f"Lc.current.{key}"
    # 统一塞进字符串里，int 也能直接进来
    lits = ", ".join("'${%s}'" % a for a in args)
    return f"Lc.current.{key}({lits})"


def gen_arb(rows):
    zh = json.load(open(ARB_ZH, encoding="utf-8"))
    en = json.load(open(ARB_EN, encoding="utf-8"))
    added = 0
    for src, key, en_val in rows:
        tmpl, args = parse(src)
        if zh.get(key) != tmpl:
            added += 1
        zh[key] = tmpl          # 以表里的原文为准，占位符编号才对得上
        if key not in en:
            en[key] = en_val
        if args:
            zh["@" + key] = {"placeholders": {f"v{i + 1}": {"type": "String"}
                                             for i in range(len(args))}}
        else:
            zh.pop("@" + key, None)
    json.dump(zh, open(ARB_ZH, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    json.dump(en, open(ARB_EN, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    return added


def dart_files():
    for dp, dn, fns in os.walk(LIB):
        if os.sep + "l10n" in dp:
            continue
        for fn in sorted(fns):
            if fn.endswith(".dart"):
                yield os.path.join(dp, fn)


def apply(rows):
    # 长的先换，免得短串把长串切碎
    rows = sorted(rows, key=lambda r: -len(r[0]))
    touched = {}
    for path in dart_files():
        s = open(path, encoding="utf-8").read()
        o = s
        for src, key, _ in rows:
            lit = "'" + src + "'"
            if lit not in s:
                continue
            _, args = parse(src)
            s = s.replace(lit, dart_call(key, args))
        if s != o:
            if IMPORT not in s and "l10n/l10n.dart" not in s:
                idx = [m.end() for m in re.finditer(r"^import .*?;\s*$", s, re.M)]
                s = (s[: idx[-1]] + "\n" + IMPORT + s[idx[-1] :]) if idx else (IMPORT + "\n\n" + s)
            open(path, "w", encoding="utf-8").write(s)
            touched[path] = True
    return touched


def report(rows):
    left = 0
    for path in dart_files():
        for line in open(path, encoding="utf-8"):
            ls = line.strip()
            if ls.startswith("//") or ls.startswith("*"):
                continue
            if CJK.search(line):
                left += 1
    print(f"表里 {len(rows)} 条；代码里还含中文的行：{left}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args()
    rows = load_table()
    if a.check:
        report(rows)
        return
    added = gen_arb(rows)
    touched = apply(rows)
    print(f"ARB 新增 {added} 条，改动 {len(touched)} 个文件")


if __name__ == "__main__":
    main()
