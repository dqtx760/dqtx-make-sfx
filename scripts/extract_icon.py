#!/usr/bin/env python3
"""从任意 Windows PE (.exe/.dll) 提取图标资源，还原成完整的多尺寸 .ico 文件。

用法:
    python extract_icon.py <软件主程序.exe> [输出.ico]

原理: 解析 PE 资源树, 找 RT_GROUP_ICON(类型14) 和 RT_ICON(类型3),
把 GRPICONDIR 还原成 ICONDIR + ICONDIRENTRY + 图像数据的 .ico 布局。
用途: make-sfx 打包软件时, 安装包图标默认用被封装软件自己的图标。
"""
import struct
import sys
import pathlib


def parse_pe(data):
    e_lfanew = struct.unpack_from("<I", data, 0x3C)[0]
    coff = e_lfanew + 4
    _, nsec, _, _, _, size_opt, _ = struct.unpack_from("<HHIIIHH", data, coff)
    opt = coff + 20
    magic = struct.unpack_from("<H", data, opt)[0]
    dd = opt + (96 if magic == 0x10B else 112)  # PE32 / PE32+
    res_rva, _ = struct.unpack_from("<II", data, dd + 16)
    if res_rva == 0:
        raise SystemExit("这个 exe 没有资源节")
    secs = []
    for i in range(nsec):
        o = opt + size_opt + i * 40
        vs, va, rs, ra = struct.unpack_from("<IIII", data, o + 8)
        secs.append((va, max(vs, rs), ra))

    def rva2off(rva):
        for va, size, ra in secs:
            if va <= rva < va + size:
                return ra + (rva - va)
        raise SystemExit(f"RVA {rva:#x} 无法映射")

    base = rva2off(res_rva)
    icons = {}   # resource id -> (rva, size)
    groups = {}  # resource id -> (rva, size)

    def walk(off, path):
        _, _, _, _, nn, ni = struct.unpack_from("<IIHHHH", data, off)
        for i in range(nn + ni):
            nid, ptr = struct.unpack_from("<II", data, off + 16 + i * 8)
            ident = nid if not (nid & 0x80000000) else None
            tgt = base + (ptr & 0x7FFFFFFF)
            if ptr & 0x80000000:
                walk(tgt, path + (ident,))
            elif len(path) == 2:
                rva2, size, _, _ = struct.unpack_from("<IIII", data, tgt)
                if path[0] == 3:      # RT_ICON
                    icons[path[1]] = (rva2, size)
                elif path[0] == 14:   # RT_GROUP_ICON
                    groups[path[1]] = (rva2, size)

    walk(base, ())
    return icons, groups, rva2off


def extract(exe, out):
    data = pathlib.Path(exe).read_bytes()
    icons, groups, rva2off = parse_pe(data)
    if not groups:
        raise SystemExit("exe 里没有图标资源 (RT_GROUP_ICON)")
    gid = sorted(groups)[0]  # 取 ID 最小的图标组（主图标）
    goff = rva2off(groups[gid][0])
    _, _, count = struct.unpack_from("<HHH", data, goff)

    raw_entries = []
    for i in range(count):
        bw, bh, bc, br, planes, bits, _sz, rid = struct.unpack_from(
            "<BBBBHHIH", data, goff + 6 + 14 * i)
        if rid not in icons:
            continue
        rva2, size = icons[rid]
        off = rva2off(rva2)
        img = data[off:off + size]
        raw_entries.append((bw, bh, bc, br, planes, bits, img))

    entries, imgs, offset = [], [], 6 + 16 * len(raw_entries)
    for bw, bh, bc, br, planes, bits, img in raw_entries:
        entries.append(struct.pack("<BBBBHHII", bw, bh, bc, br, planes, bits, len(img), offset))
        imgs.append(img)
        offset += len(img)
    ico = struct.pack("<HHH", 0, 1, len(entries)) + b"".join(entries) + b"".join(imgs)
    pathlib.Path(out).write_bytes(ico)
    print(f"[OK] 提取 {len(entries)} 个尺寸 -> {out} ({len(ico):,} bytes)")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    exe = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) > 2 else (
        pathlib.Path(exe).stem + ".ico")
    extract(exe, out)
