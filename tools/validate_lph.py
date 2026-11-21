"""Validate lph_decode port: (4)'s LPH -> brotli -> must equal prog_1.bin."""
import re
import sys

sys.path.insert(0, "tools")
from lph_decode import lph_decode

import brotli

src = open("Samples/Luraph/luraph-v14.7 (4).lua", encoding="utf-8").read()
blobs = []
for m in re.finditer(r"\[(=+)\[LPH", src):
    eq = m.group(1)
    j = src.find("]" + eq + "]", m.end())
    blobs.append("LPH" + src[m.end():j])
print("blobs:", [len(b) for b in blobs])

for v in (5, 15):
    try:
        raw = lph_decode(blobs[0], v)
        dec = brotli.decompress(raw)
        print("V=", v, "decoded", len(raw), "brotli->", len(dec))
    except Exception as e:
        print("V=", v, "FAIL:", str(e)[:100])
ref = open("tools/work/prog_1.bin", "rb").read()
print("ref prog_1.bin:", len(ref))
