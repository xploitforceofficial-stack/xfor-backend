"""Decompress (2)'s zstd layers with a real zstd implementation.

Layer 1 (32KB LPH -> 26047 bytes -> stage source) and layer 2 (1.27MB LPH
-> 1018240 bytes -> program buffer).
"""
import sys

sys.path.insert(0, "tools")
from lph_decode import lph_decode

import zstandard

def main() -> int:
    src = open("Samples/Luraph/luraph-v14.7 (2).lua", encoding="utf-8").read()
    import re
    blobs = []
    for m in re.finditer(r"\[(=+)\[LPH", src):
        eq = m.group(1)
        j = src.find("]" + eq + "]", m.end())
        blobs.append("LPH" + src[m.end():j])
    dctx = zstandard.ZstdDecompressor()
    l1 = lph_decode(blobs[0], 5)[:26047]
    print("layer1 zstd bytes:", len(l1))
    try:
        stage = dctx.decompress(l1)
        print("layer1 OK: stage", len(stage), "bytes")
        open("tools/work_s2_stage_raw.lua", "wb").write(stage)
    except Exception as e:
        print("layer1 FAIL:", e)
        return 1
    l2 = lph_decode(blobs[1], 5)[:1018240]
    print("layer2 zstd bytes:", len(l2))
    try:
        prog = dctx.decompress(l2)
        print("layer2 OK: prog", len(prog), "bytes")
        open("tools/work_s2_prog.bin", "wb").write(prog)
    except Exception as e:
        print("layer2 FAIL:", e)
        return 1
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
