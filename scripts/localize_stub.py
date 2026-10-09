"""
localize_stub.py — 把 7zSD.sfx 安装器的英文字符串资源替换成中文。

原理：
  7zSD.sfx 的界面文字（如进度框标题 "27% Extracting" 里的 "Extracting"）
  存放在 PE 资源节的 RT_STRING 表里（每表 16 条，[u16 长度][UTF-16 字符]）。
  本脚本直接在文件字节上重写这些表 —— 不依赖 UpdateResource API。

用法：
  python localize_stub.py <stub.sfx> [-o <输出.sfx>]
  不带 -o 就地修改。

内置替换表（要改别的就往里加）：
  3300  Extracting                    -> 数据解压中      （进度框标题 "27% Extracting"）
  7     Extraction Failed            -> 解压失败
  8     File is corrupt              -> 文件已损坏
  3003  Cannot create folder '{0}'   -> 无法创建文件夹 '{0}'
"""
import struct, sys, pathlib

REPL = {
    3300: "数据解压中",
    7: "解压失败",
    8: "文件已损坏",
    3003: "无法创建文件夹 '{0}'",
}

RT_STRING = 6


def parse_resources(data: bytes):
    e_lfanew = struct.unpack_from("<I", data, 0x3C)[0]
    if data[e_lfanew:e_lfanew + 4] != b"PE\0\0":
        raise SystemExit("不是 PE 文件")
    coff = e_lfanew + 4
    _, nsec, _, _, _, size_opt, _ = struct.unpack_from("<HHIIIHH", data, coff)
    opt = coff + 20
    magic = struct.unpack_from("<H", data, opt)[0]
    dd_off = opt + (96 if magic == 0x10B else 112)
    res_rva, _ = struct.unpack_from("<II", data, dd_off + 8 * 2)

    sec_off = opt + size_opt
    sections = []
    for i in range(nsec):
        o = sec_off + i * 40
        vsize, vaddr, rsize, raddr = struct.unpack_from("<IIII", data, o + 8)
        sections.append((vaddr, vsize, raddr, rsize))


    def rva2off(rva):
        for va, vs, ra, rs in sections:
            if va <= rva < va + max(vs, rs):
                return ra + (rva - va)
        raise SystemExit(f"RVA {rva:#x} 无法映射")

    rsrc_base = rva2off(res_rva)
    out = []

    def walk(off, path=()):
        _, _, _, _, n_named, n_id = struct.unpack_from("<IIHHHH", data, off)
        for i in range(n_named + n_id):
            name_or_id, ptr = struct.unpack_from("<II", data, off + 16 + i * 8)
            ident = name_or_id if not (name_or_id & 0x80000000) else None
            target = rsrc_base + (ptr & 0x7FFFFFFF)
            if ptr & 0x80000000:
                walk(target, path + (ident,))
            else:
                data_rva, size, _, _ = struct.unpack_from("<IIII", data, target)
                out.append((path + (ident,), data_rva, size, rva2off(data_rva)))

    walk(rsrc_base)
    return [(p[1], p[2], size, fo) for (p, rva, size, fo) in out if p[0] == RT_STRING]


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    out_path = None
    if "-o" in sys.argv:
        out_path = pathlib.Path(sys.argv[sys.argv.index("-o") + 1])
    stub = pathlib.Path(args[0])
    data = bytearray(stub.read_bytes())

    blocks = parse_resources(bytes(data))
    if not blocks:
        raise SystemExit("没找到 RT_STRING 资源")

    changed = []
    for rid, lang, size, fo in blocks:
        buf = data[fo:fo + size]
        off, entries = 0, []
        for _ in range(16):
            n = int.from_bytes(buf[off:off + 2], "little"); off += 2
            entries.append(buf[off:off + n * 2].decode("utf-16-le", "replace")); off += n * 2

        new, hit = [], False
        for i, s in enumerate(entries):
            sid = (rid - 1) * 16 + i
            if sid in REPL:
                new.append(REPL[sid]); hit = True
            else:
                new.append(s)
        if not hit:
            continue

        blob = b"".join(
            (len(s.encode("utf-16-le")) // 2).to_bytes(2, "little") + s.encode("utf-16-le")
            for s in new)
        if len(blob) > size:
            raise SystemExit(f"res {rid}: 新内容 {len(blob)} 字节超过原 {size} 字节，需手工处理")
        data[fo:fo + size] = blob + b"\0" * (size - len(blob))
        changed.append((rid, size, len(blob)))

    target = out_path or stub
    target.write_bytes(bytes(data))
    for rid, old, new in changed:
        print(f"[ok] RT_STRING res {rid}: {old} -> {new} bytes")
    print(f"已写出 {target}")


if __name__ == "__main__":
    main()
