"""Port of Luraph v14.7's LPH string decoder (loader `s()` function).

s(Q): strip V-1 head chars, unescape 'z' -> '!!!!!', decode every 5-char
group as base85 (LSB...MSB place order 1,85,7225,614125,52200625 with the
FIRST char most significant) to U32LE bytes.
"""
import re
import struct
import sys

def lph_decode(text, v=5):
    q = text[v - 1:] if v >= 1 else text
    q = q.replace("z", "!!!!!")
    out = bytearray()
    memo = {}
    for i in range(0, len(q) - (len(q) % 5), 5):
        g = q[i:i + 5]
        if g in memo:
            out += memo[g]
            continue
        c = [ord(x) for x in g]
        u = (c[4] - 33) + (c[3] - 33) * 85 + (c[2] - 33) * 7225 + \
            (c[1] - 33) * 614125 + (c[0] - 33) * 52200625
        b = struct.pack("<I", u & 0xFFFFFFFF)
        memo[g] = b
        out += b
    return bytes(out)

def main() -> int:
    path = sys.argv[1]
    which = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    v = int(sys.argv[3]) if len(sys.argv) > 3 else 5
    src = open(path, encoding="utf-8").read()
    blobs = []
    for m in re.finditer(r"\[(=+)\[LPH", src):
        eq = m.group(1)
        close = "]" + eq + "]"
        j = src.find(close, m.end())

        blobs.append("LPH" + src[m.end():j])
    print("LPH blobs:", [len(b) for b in blobs])
    raw = lph_decode(blobs[which - 1], v)
    print("decoded len:", len(raw))
    print("head hex:", raw[:16].hex())
    print("zstd magic:", raw[:4] == bytes([0x28, 0xB5, 0x2F, 0xFD]))
    if len(sys.argv) > 4:
        open(sys.argv[4], "wb").write(raw)
        print("wrote", sys.argv[4])
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
