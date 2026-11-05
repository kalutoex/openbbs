#!/usr/bin/env python3
"""生成 8 套应用图标资源（第 4 版图形：外环 + 中间三条横线）。

    python3 tool/gen_app_icons.py

产出：
  android/app/src/main/res/mipmap-<dpi>/ic_launcher_<key>.png          传统图标（方形圆角）
  android/app/src/main/res/mipmap-<dpi>/ic_launcher_<key>_round.png    圆形（部分启动器用）
  android/app/src/main/res/mipmap-<dpi>/ic_launcher_<key>_foreground.png  自适应前景
  android/app/src/main/res/mipmap-anydpi-v26/ic_launcher_<key>.xml    自适应图标（8.0+）
  android/app/src/main/res/values/ic_launcher_colors.xml              自适应背景色
  assets/icons/icon_<key>.png                                         设置页预览（192）

形状全部在这里，配色只改 COLORS。加一套图标就把新的 key 加进 COLORS，
再去 AndroidManifest.xml 里照着补一个 activity-alias，Dart 侧的 ICONS 也要加。
"""
import os
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "android/app/src/main/res")
ASSETS = os.path.join(ROOT, "assets/icons")

# key -> 主色。第一个是默认（薄荷）。
COLORS = [
    ("mint", (122, 224, 196)),
    ("blue", (106, 169, 255)),
    ("purple", (167, 139, 250)),
    ("pink", (244, 114, 182)),
    ("coral", (255, 159, 110)),
    ("red", (255, 122, 122)),
    ("lime", (156, 224, 116)),
    ("steel", (159, 179, 200)),
]

LEGACY = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
FOREGROUND = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}

BIG = 1080          # 内部渲染尺寸，最后统一缩到目标尺寸
MARK = 0.62         # 图形占画布比例（自适应图标要留安全区，0.62 是保守值）


def dark_of(color, k):
    return tuple(int(c * k) for c in color)


def gradient(size, top, bottom):
    im = Image.new("RGB", (size, size))
    d = ImageDraw.Draw(im)
    for y in range(size):
        t = y / (size - 1)
        d.line([(0, y), (size, y)],
               fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return im


def draw_mark(d, size, color, scale=MARK):
    """环 + 三条横线。坐标全部按 size 的比例算，换尺寸不用改。"""
    cx = cy = size / 2
    r = size * scale / 2
    w = size * scale * 0.112
    d.ellipse((cx - r, cy - r, cx + r, cy + r), outline=color, width=int(w))
    for dy, wf in [(-0.148, 0.40), (0.0, 0.30), (0.148, 0.20)]:
        bw = size * scale * wf
        bh = size * scale * 0.093
        y = cy + size * scale * dy - bh / 2
        d.rounded_rectangle((cx - bw / 2, y, cx + bw / 2, y + bh),
                            radius=bh / 2, fill=color)


def legacy_icon(color, size, round_=False):
    top, bot = dark_of(color, 0.17), dark_of(color, 0.08)
    im = gradient(BIG, top, bot)
    draw_mark(ImageDraw.Draw(im), BIG, color, scale=0.62)
    im = im.resize((size, size), Image.LANCZOS).convert("RGBA")
    mask = Image.new("L", (size, size), 0)
    md = ImageDraw.Draw(mask)
    if round_:
        md.ellipse((0, 0, size - 1, size - 1), fill=255)
    else:
        md.rounded_rectangle((0, 0, size, size), radius=int(size * 0.225), fill=255)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(im, (0, 0), mask)
    return out


def foreground(color, size):
    im = Image.new("RGBA", (BIG, BIG), (0, 0, 0, 0))
    draw_mark(ImageDraw.Draw(im), BIG, color)
    return im.resize((size, size), Image.LANCZOS)


def preview(color, size=192):
    return legacy_icon(color, size)


def maskable(color, size):
    """PWA 的 maskable 图标：满底不透明，图形压在中间 80% 安全圆里。"""
    im = gradient(BIG, dark_of(color, 0.17), dark_of(color, 0.08))
    draw_mark(ImageDraw.Draw(im), BIG, color, scale=0.56)
    return im.resize((size, size), Image.LANCZOS).convert("RGBA")


def main():
    os.makedirs(ASSETS, exist_ok=True)
    written = 0
    for key, color in COLORS:
        for dpi, px in LEGACY.items():
            d = os.path.join(RES, f"mipmap-{dpi}")
            os.makedirs(d, exist_ok=True)
            legacy_icon(color, px).save(os.path.join(d, f"ic_launcher_{key}.png"))
            legacy_icon(color, px, round_=True).save(os.path.join(d, f"ic_launcher_{key}_round.png"))
            written += 2
        for dpi, px in FOREGROUND.items():
            d = os.path.join(RES, f"mipmap-{dpi}")
            foreground(color, px).save(os.path.join(d, f"ic_launcher_{key}_foreground.png"))
            written += 1
        # 自适应图标（Android 8.0+）
        ad = os.path.join(RES, "mipmap-anydpi-v26")
        os.makedirs(ad, exist_ok=True)
        with open(os.path.join(ad, f"ic_launcher_{key}.xml"), "w") as f:
            f.write(
                '<?xml version="1.0" encoding="utf-8"?>\n'
                '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
                f'    <background android:drawable="@color/ic_launcher_{key}_background" />\n'
                f'    <foreground android:drawable="@mipmap/ic_launcher_{key}_foreground" />\n'
                '</adaptive-icon>\n'
            )
        preview(color).save(os.path.join(ASSETS, f"icon_{key}.png"))

    lines = ['<?xml version="1.0" encoding="utf-8"?>',
             '<!-- 由 tool/gen_app_icons.py 生成，别手改。 -->',
             '<resources>']
    for key, color in COLORS:
        rgb = "#%02X%02X%02X" % dark_of(color, 0.14)
        lines.append(f'    <color name="ic_launcher_{key}_background">{rgb}</color>')
    lines.append('</resources>')
    with open(os.path.join(RES, "values/ic_launcher_colors.xml"), "w") as f:
        f.write("\n".join(lines) + "\n")

    print(f"完成：{len(COLORS)} 套图标，{written} 张位图")

    # 网页端只跟默认那套走：PWA 图标、maskable、favicon。
    key, color = COLORS[0]
    web_icons = os.path.join(ROOT, "web/icons")
    os.makedirs(web_icons, exist_ok=True)
    preview(color, 192).save(os.path.join(web_icons, "Icon-192.png"))
    preview(color, 512).save(os.path.join(web_icons, "Icon-512.png"))
    maskable(color, 192).save(os.path.join(web_icons, "Icon-maskable-192.png"))
    maskable(color, 512).save(os.path.join(web_icons, "Icon-maskable-512.png"))
    preview(color, 64).save(os.path.join(ROOT, "web/favicon.png"))
    print("网页图标已更新（%s）" % key)


if __name__ == "__main__":
    main()
