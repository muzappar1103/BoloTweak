#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
把用户提供的圆形徽章 logo 处理成 BoloTweak 源图标。

思路：
  原图 1920x1920，内容是一个近乎顶满画布的正圆徽章。
  iOS 会按「圆角方形」裁切图标，若直接缩放，圆环边缘和外圈文字
  会被切掉。所以：
    1. 取原图底色 #FFF7E4 铺满正方形画布（向外 bleed，四角无缝）
    2. 徽章缩到 84% 居中 → 留出安全边距
    3. 输出 512 / 1024 两档

用法: python scripts/make_icon.py [源图路径]
不传参数时用内置默认路径。
"""
import os
import sys
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_SRC = os.path.join(ROOT, "assets", "logo-src.png")

# 取原图四角像素作为底色，避免硬编码
INSET = 0.92          # 徽章占画布的比例（越大越满，iOS 圆角裁切仍安全）
SUPERSAMPLE = 2       # 超采样倍数


def edge_color(im):
    """取四角均值作为背景色"""
    w, h = im.size
    pts = [(3, 3), (w - 4, 3), (3, h - 4), (w - 4, h - 4)]
    px = [im.getpixel(p) for p in pts]
    if isinstance(px[0], int):
        return px[0]
    n = len(px[0])
    return tuple(sum(p[i] for p in px) // len(px) for i in range(n))


def build(src_path, size):
    src = Image.open(src_path).convert("RGB")
    bg = edge_color(src)

    S = size * SUPERSAMPLE
    canvas = Image.new("RGB", (S, S), bg)

    # 徽章缩放到 INSET，居中贴入
    inner = int(S * INSET)
    glyph = src.resize((inner, inner), Image.LANCZOS)
    off = (S - inner) // 2
    canvas.paste(glyph, (off, off))

    return canvas.resize((size, size), Image.LANCZOS)


def main():
    src_path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_SRC
    if not os.path.isfile(src_path):
        print("找不到源图: %s" % src_path)
        sys.exit(1)

    # 主图标 512（Sileo 首选），@2x @3x 给高分屏
    targets = [
        ("CydiaIcon.png", 512),
        ("CydiaIcon@2x.png", 1024),
        ("CydiaIcon@3x.png", 1024),
        ("icon-29.png", 29),
        ("icon-58.png", 58),
        ("icon-87.png", 87),
    ]
    for name, size in targets:
        img = build(src_path, size)
        out = os.path.join(ROOT, name)
        # 源图标要保真，用高质量压缩
        img.save(out, "PNG", optimize=True)
        print("写出 %s (%dx%d)" % (name, size, size))


if __name__ == "__main__":
    main()