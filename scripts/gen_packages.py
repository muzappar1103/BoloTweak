#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
BoloTweak 源 Packages 生成器
============================

等价于 macOS/Linux 上的:  dpkg-scanpackages -m . /dev/null > Packages

不依赖 dpkg。.deb 是 ar 容器，里面裹着 control.tar.{gz,xz,bz2,zst}，
用 Python 标准库就能读出来 —— 这是给 Windows 用的替代方案。

用法:
    python scripts/gen_packages.py            # 生成 Packages + Packages.bz2
    python scripts/gen_packages.py --verify   # 只校验不写文件

支持多 Arch：
    - 依赖 dpkg 的老 Sileo 需要 Architectures 声明，但 Packages 条目本身
      只需每个 deb 写自己的 Architecture 字段即可。
"""

import argparse
import bz2
import gzip
import hashlib
import io
import lzma
import os
import sys
import tarfile

# 仓库根目录（本脚本在 scripts/ 下）
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEBS_DIR = os.path.join(ROOT, "debs")
PACKAGES_FILE = os.path.join(ROOT, "Packages")
PACKAGES_BZ2 = os.path.join(ROOT, "Packages.bz2")

# Packages 里字段的推荐顺序，未知字段追加到末尾
FIELD_ORDER = [
    "Package", "Name", "Version", "Architecture", "Section", "Priority",
    "Essential", "Depends", "Pre-Depends", "Recommends", "Suggests",
    "Conflicts", "Breaks", "Replaces", "Provides",
    "Installed-Size", "Maintainer", "Author", "Sponsor",
    "Description", "Homepage", "Depiction", "SileoDepiction", "Icon",
    "Filename", "Size", "MD5sum", "SHA1", "SHA256",
]

# 允许的架构，用于警告
KNOWN_ARCHS = {"iphoneos-arm", "iphoneos-arm64", "iphoneos-arm64e", "all"}


# ---------------------------------------------------------------- ar 解析

def read_ar_members(data):
    """解析 ar 归档，返回 [(name, bytes), ...]"""
    if not data.startswith(b"!<arch>\n"):
        raise ValueError("不是有效的 ar 归档（deb 文件头不对）")
    pos = 8
    members = []
    total = len(data)
    while pos + 60 <= total:
        header = data[pos:pos + 60]
        raw_name = header[0:16].decode("utf-8", "replace").strip()
        try:
            size = int(header[48:58].decode("ascii", "replace").strip())
        except ValueError:
            break
        start = pos + 60
        end = start + size
        if end > total:
            break
        name = raw_name.rstrip("/")
        members.append((name, data[start:end]))
        pos = end + (size & 1)  # ar 成员按 2 字节对齐
    return members


def decompress_control(payload, name):
    """把 control.tar.* 解压成 tarfile 对象"""
    if name.endswith(".tar"):
        return tarfile.open(fileobj=io.BytesIO(payload), mode="r:")
    if name.endswith(".tar.gz") or name.endswith(".tgz"):
        return tarfile.open(fileobj=io.BytesIO(payload), mode="r:gz")
    if name.endswith(".tar.xz"):
        return tarfile.open(fileobj=io.BytesIO(payload), mode="r:xz")
    if name.endswith(".tar.bz2"):
        return tarfile.open(fileobj=io.BytesIO(payload), mode="r:bz2")
    if name.endswith(".tar.zst"):
        try:
            import zstandard  # type: ignore
        except ImportError:
            raise RuntimeError(
                "遇到 .tar.zst 压缩的 deb，需要先装 zstandard：pip install zstandard"
            )
        dctx = zstandard.ZstdDecompressor()
        raw = dctx.decompress(payload)
        return tarfile.open(fileobj=io.BytesIO(raw), mode="r:")
    raise RuntimeError("不认识的 control 归档格式: " + name)


def parse_control_text(text):
    """解析 debian control 文本为 dict；支持跨行续行（以空格开头）"""
    fields = {}
    current = None
    for line in text.splitlines():
        if not line.strip():
            continue
        if line[0] in " \t" and current:
            fields[current] += "\n" + line
        elif ":" in line:
            key, _, value = line.partition(":")
            current = key.strip()
            fields[current] = value.strip()
    return fields


def extract_control(deb_path):
    """从一个 .deb 里取出 control 字段 dict"""
    with open(deb_path, "rb") as f:
        data = f.read()
    members = read_ar_members(data)
    control_member = None
    for name, payload in members:
        if name.startswith("control.tar"):
            control_member = (name, payload)
            break
    if control_member is None:
        raise RuntimeError("deb 里找不到 control.tar.*")
    name, payload = control_member
    tf = decompress_control(payload, name)
    try:
        for member in tf.getmembers():
            base = os.path.basename(member.name)
            if base == "control":
                fh = tf.extractfile(member)
                if fh is None:
                    continue
                return parse_control_text(fh.read().decode("utf-8", "replace"))
    finally:
        tf.close()
    raise RuntimeError("control 归档里找不到 control 文件")


# ---------------------------------------------------------------- 生成

def find_debs():
    """递归找出 debs/ 下所有 .deb，返回相对 ROOT 的 posix 路径"""
    found = []
    if not os.path.isdir(DEBS_DIR):
        return found
    for dirpath, dirnames, filenames in os.walk(DEBS_DIR):
        dirnames.sort()
        for fn in sorted(filenames):
            if fn.lower().endswith(".deb"):
                full = os.path.join(dirpath, fn)
                rel = os.path.relpath(full, ROOT).replace(os.sep, "/")
                found.append(rel)
    return found


def hashes(path):
    md5 = hashlib.md5()
    sha1 = hashlib.sha1()
    sha256 = hashlib.sha256()
    size = 0
    with open(path, "rb") as f:
        while True:
            chunk = f.read(1024 * 256)
            if not chunk:
                break
            size += len(chunk)
            md5.update(chunk)
            sha1.update(chunk)
            sha256.update(chunk)
    return size, md5.hexdigest(), sha1.hexdigest(), sha256.hexdigest()


def build_entry(rel_path, site_base):
    full = os.path.join(ROOT, rel_path.replace("/", os.sep))
    ctrl = extract_control(full)
    size, md5, sha1, sha256 = hashes(full)
    for required in ("Package", "Version", "Architecture"):
        if not ctrl.get(required):
            raise RuntimeError("%s 缺少必需字段 %s" % (rel_path, required))

    arch = ctrl["Architecture"].strip()
    if arch not in KNOWN_ARCHS:
        print("  ! 警告: %s 的 Architecture=%r 不在常见值里" % (rel_path, arch))

    # 补全 Filename / 校验和 —— 这几个必须由文件真实字节算，手写必错
    ctrl["Filename"] = "./" + rel_path
    ctrl["Size"] = str(size)
    ctrl["MD5sum"] = md5
    ctrl["SHA1"] = sha1
    ctrl["SHA256"] = sha256

    # 若包自己没写 Depiction，指向仓库里的详情页（存在才算）
    if not ctrl.get("Depiction"):
        pkg = ctrl["Package"]
        dep_path = os.path.join(ROOT, "sileodepiction", pkg + ".html")
        if os.path.isfile(dep_path):
            ctrl["Depiction"] = site_base + "sileodepiction/" + pkg + ".html"
    return ctrl


def render_stanza(ctrl):
    keys = [k for k in FIELD_ORDER if k in ctrl]
    keys += [k for k in ctrl if k not in FIELD_ORDER]
    lines = []
    for k in keys:
        value = ctrl[k]
        if "\n" in value:
            # dpkg 多行字段规范：首行 "Key: value"，
            # 后续行恰好一个前导空格；真正的空行表示为 " ."
            parts = [p.strip() for p in value.split("\n")]
            lines.append("%s: %s" % (k, parts[0]))
            for p in parts[1:]:
                lines.append(" " + p if p else " .")
        else:
            lines.append("%s: %s" % (k, value))
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--verify", action="store_true", help="只校验，不写文件")
    ap.add_argument(
        "--site-base",
        default="https://muzappar1103.github.io/BoloTweak/",
        help="仓库站点根地址（用于自动填 Depiction）",
    )
    args = ap.parse_args()

    debs = find_debs()
    if not debs:
        print("debs/ 下没有找到任何 .deb 文件。")
        print("请把 deb 放进 %s 后再运行。" % DEBS_DIR)
        # 空源也要能生成一个空 Packages，否则 Actions 会失败
        if not args.verify:
            with open(PACKAGES_FILE, "w", encoding="utf-8", newline="\n") as f:
                f.write("")

    stanzas = []
    seen = {}
    print("发现 %d 个 deb：" % len(debs))
    for rel in debs:
        try:
            ctrl = build_entry(rel, args.site_base)
        except Exception as e:
            print("  ✗ %s -> %s" % (rel, e))
            sys.exit(1)
        key = (ctrl["Package"], ctrl["Architecture"])
        if key in seen:
            print(
                "  ! 警告: %s (%s) 出现多次：%s 与 %s"
                % (ctrl["Package"], ctrl["Architecture"], seen[key], rel)
            )
        seen[key] = rel
        stanzas.append(ctrl)
        print(
            "  ✓ %-28s %-18s %-14s %s"
            % (ctrl["Package"], ctrl["Version"], ctrl["Architecture"], rel)
        )

    text = "\n\n".join(render_stanza(s) for s in stanzas)
    if text:
        text += "\n"

    if args.verify:
        print("\n校验通过：%d 个包。" % len(stanzas))
        return

    with open(PACKAGES_FILE, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    with open(PACKAGES_BZ2, "wb") as f:
        f.write(bz2.compress(text.encode("utf-8"), 9))

    print("\n已写出：")
    print("  %s  (%d 字节)" % (PACKAGES_FILE, os.path.getsize(PACKAGES_FILE)))
    print("  %s  (%d 字节)" % (PACKAGES_BZ2, os.path.getsize(PACKAGES_BZ2)))


if __name__ == "__main__":
    main()