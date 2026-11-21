"""
Luraph v14 LPH+zstd blob pre-decode for the fast-harness path.

A v14 loader pulls its stage/program through
`EncodingService:DecompressBuffer(buffer.fromstring(<zstd frame>), Zstd)`.
luau.exe cannot run a zstd decoder of its own, so the host decodes every
frame up front (real `zstandard` package) and hands the harness a
{key: decompressed-bytes} map (`__ZSTD`, see harness.build_harness);
envlog's DecompressBuffer override looks the runtime bytes up and returns
a real buffer, so the loader's loadstring gets the actual stage.

Keys are len + first-8 + last-8 hex of the exact bytes the loader puts in
the buffer (it slices the LPH-decoded string to the frame first, so the
map registers every candidate slicing the source mentions, plus the full
LPH output - whichever the loader hands over hits).

Only stdlib + the `zstandard` package (already required for any v14 work).
Without it this returns {} and the harness falls back to the proxy
(the loader then fails loudly instead of silently).
"""
import re
import struct
import sys

try:
    import zstandard
except ImportError:
    zstandard = None

ZSTD_MAGIC = bytes([0x28, 0xB5, 0x2F, 0xFD])

def lph_decode(text, v=5):
    """Port of the v14.7 loader's LPH string decoder (its `s()` function)."""
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

def blob_key(data):
    """Same key as envlog's DecompressBuffer lookup (len:first8:last8 hex)."""
    return "%d:%s:%s" % (len(data), data[:8].hex(), data[-8:].hex())

def extract_lph(source):
    """[lph-decoded bytes] for every [===[LPH...]===] blob, in file order."""
    blobs = []
    for m in re.finditer(r"\[(=+)\[LPH", source):
        eq = m.group(1)
        j = source.find("]" + eq + "]", m.end())
        if j < 0:
            continue
        blobs.append(lph_decode("LPH" + source[m.end():j]))
    return blobs

def candidate_sizes(source):
    """Byte counts the loader slices blobs to (`string.sub(x,1,N)`, N > 1KB)."""
    out = set()
    for m in re.finditer(r"string\.sub\(\s*\w+\s*,\s*1\s*,\s*(\d+)\s*\)", source):
        n = int(m.group(1))
        if n > 1024:
            out.add(n)
    return sorted(out)

def build_map(source):
    """{blob_key: decompressed bytes} for every decodable frame found."""
    found = {}
    if zstandard is None:
        print("[!] zstandard package missing: v14 blobs stay opaque "
              "(pip install zstandard)", file=sys.stderr)
        return found
    dctx = zstandard.ZstdDecompressor()
    sizes = candidate_sizes(source)
    for data in extract_lph(source):
        cands = {len(data)}
        for n in sizes:
            if n < len(data):
                cands.add(n)
        for n in sorted(cands):
            frame = data[:n]
            if not frame.startswith(ZSTD_MAGIC):
                continue
            try:
                dec = dctx.decompress(frame)
            except Exception:
                continue
            found.setdefault(blob_key(frame), dec)
    print("[*] v14 blobs: %d frame(s) pre-decoded (%s)" %
          (len(found), ", ".join("%d->%d" % (int(k.split(":")[0]), len(v))
                                 for k, v in found.items()) or "none"),
          file=sys.stderr)
    return found
