"""Parse a zstd frame far enough to locate the literals section.

Used to check what env/zstd.luau computes for the huffman table description
(bounds, normalized distribution, bitstream range) against the format spec.
"""
import sys

def u32le(d, p):
    return int.from_bytes(d[p:p + 4], "little")

def parse(d):
    assert d[:4] == b"\x28\xb5\x2f\xfd", "not a zstd frame"
    p = 4
    fhd = d[p]
    p += 1
    fcs_flag = fhd >> 6
    single = (fhd >> 5) & 1
    content_chk = (fhd >> 2) & 1
    dict_flag = fhd & 3
    if not single:
        p += 1
    fcs_size = (0, 2, 4, 8)[fcs_flag] if fcs_flag != 1 else 1
    if fcs_size:
        fcs_size = 1 if fcs_flag == 0 else (2 if fcs_flag == 1 else (4 if fcs_flag == 2 else 8))
        p += fcs_size
    if dict_flag:
        p += 1
    if content_chk:
        p += 4
    print("frame header: %d bytes, content size field=%d, single=%d"
          % (p, fcs_size, single))

    bh = int.from_bytes(d[p:p + 3], "little")
    last = bh & 1
    btype = (bh >> 1) & 3
    bsize = bh >> 3
    print("block: last=%d type=%d size=%d at %d" % (last, btype, bsize, p))
    if btype != 2:
        print("not a compressed block; nothing to do")
        return
    p += 3
    end = p + bsize

    b0 = d[p]
    ltype = b0 & 3
    sf = (b0 >> 2) & 3
    print("literals: type=%d size_format=%d at %d" % (ltype, sf, p))
    if sf in (0, 2):
        regen = b0 >> 3
        comp = b0 >> 3 if sf == 0 else ((b0 >> 4) | (d[p + 1] << 4))
        p += 1
    elif sf == 1:
        regen = (b0 >> 4) | (d[p + 1] << 4)
        comp = ((b0 >> 2) & 0x3F) | (d[p + 1] << 6)
        p += 2
    else:
        regen = (b0 >> 4) | (d[p + 1] << 4) | (d[p + 2] << 12)
        comp = ((b0 >> 2) & 0x3F) | (d[p + 1] << 6) | (d[p + 2] << 12) | (d[p + 3] << 18)
        p += 3
    print("  regenerated=%d compressed=%d header ends %d" % (regen, comp, p))
    if ltype == 2:
        hp = p
        hb = d[hp]
        print("  huffman description first byte = 0x%02x (0x%02x)" % (hb, hb))

        body = 1 if hb < 128 else (hb - 127)
        print("  body bytes=%d, table bytes start %d, end %d" % (body, hp + 1, hp + 1 + body))
        print("  literals data %d..%d" % (hp + 1 + body, hp + 1 + body + comp - body))
    return p

if __name__ == "__main__":
    parse(open(sys.argv[1], "rb").read())
