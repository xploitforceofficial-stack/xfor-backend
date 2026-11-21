"""Decode the Luraph v14 program buffer: header + constant pool.

Layout, confirmed by two independent lines that agree exactly:

* stage147.lua `nY` reads `H = p6() - 70152` (a 7-bit varint), then a flag
  byte, then H records of `tag (u8) + payload`. `p6` loops `until H < 128`.
* prog_1.bin opens `ce ad 04 00`. varint over the first three bytes is 71374,
  so H = 71374 - 70152 = 1222, flag byte = 0, records start at offset 4.

Payload widths come from the dispatch in `nY` / `lY` / `pY` / `CY` / `kY`,
and are corroborated by the read log: every readu16 is preceded by 182, every
readi16 by 157, every readi32 by 88, both readf32 by 33, readu32 by 74 or 215,
and every readstring two bytes after 251. Greedy decoding stops at exactly
1222 records, at offset 7097 - which is where the bytecode section starts.
"""
import json
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PROG = os.path.join(HERE, "work", "prog_1.bin")
OUT = os.path.join(HERE, "work", "format.json")

def varint(buf, p):
    v = 0
    shift = 0
    while True:
        c = buf[p]
        p += 1
        v |= (c & 0x7F) << shift
        if c < 128:
            return v, p
        shift += 7

def payload_width(tag):
    """Bytes the payload occupies after the tag byte. None means string."""
    if tag <= 73:
        return 4, "f32"
    if tag == 74:
        return 8, "u32x2"
    if tag <= 88:
        return 4, "i32"
    if tag <= 98:
        return 0, "none"
    if tag <= 157:
        return 2, "i16"
    if tag <= 182:
        return 2, "u16"
    if tag <= 215:
        return 4, "u32"
    if tag <= 228 or tag == 243:
        return 1, "u8"
    return None, "str"

def decode(buf, pos, shape):
    if shape == "f32":
        return struct.unpack_from("<f", buf, pos)[0], pos + 4
    if shape == "i32":
        return struct.unpack_from("<i", buf, pos)[0], pos + 4
    if shape == "u32":
        return struct.unpack_from("<I", buf, pos)[0], pos + 4
    if shape == "i16":
        return struct.unpack_from("<h", buf, pos)[0], pos + 2
    if shape == "u16":
        return struct.unpack_from("<H", buf, pos)[0], pos + 2
    if shape == "u32x2":
        a, b = struct.unpack_from("<II", buf, pos)
        return [a, b], pos + 8
    if shape == "u8":
        return buf[pos], pos + 1
    if shape == "str":
        ln, q = varint(buf, pos)
        return buf[q:q + ln].decode("latin-1"), q + ln
    return None, pos

def main():
    buf = open(PROG, "rb").read()
    count, p = varint(buf, 0)
    count -= 70152
    flag = buf[p]
    p += 1
    print("varint=%d H=%d flag=%d records_from=%d" % (count + 70152, count, flag, p))

    recs = []
    for i in range(count):
        tag = buf[p]
        start = p
        w, shape = payload_width(tag)
        if shape == "str":
            value, p = decode(buf, p + 1, "str")
        else:
            if p + 1 + w > len(buf):
                raise SystemExit("record %d at %d overruns" % (i, p))
            value, p = decode(buf, p + 1, shape)
        recs.append({"i": i, "tag": tag, "off": start, "shape": shape,
                     "value": value})

    print("decoded %d records, pool ends at %d (next bytes %s)"
          % (len(recs), p, buf[p:p + 8].hex()))

    shapes = {}
    for r in recs:
        shapes[r["shape"]] = shapes.get(r["shape"], 0) + 1
    print("shapes:", dict(sorted(shapes.items(), key=lambda kv: -kv[1])))

    strings = [r["value"] for r in recs if r["shape"] == "str"]
    print("strings: %d" % len(strings))
    for s in strings[:30]:
        print("   ", repr(s[:70]))

    with open(OUT, "w", encoding="utf8") as f:
        json.dump({"header": {"raw": list(buf[:4]), "count": count, "flag": flag,
                              "pool_end": p},
                   "records": recs}, f, indent=1)
    print("wrote", OUT)
    return 0

if __name__ == "__main__":
    sys.exit(main())
