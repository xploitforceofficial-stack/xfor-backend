"""Generate a zstd test corpus with known answers.

Debugging the bundled decoder against one real Luraph frame is guesswork: a
single failure has too many candidate causes. Compressing data we choose gives
cases where the expected output is known exactly, and cases can be made
progressively simpler until the smallest failing input is obvious.

Writes tools/zstd-corpus/gen/<name>.zst plus <name>.raw for every case.

Usage: python tools/zstd_gen.py [count]
"""
import pathlib
import sys

import zstandard

OUT = pathlib.Path("tools/zstd-corpus/gen")

CASES = [

    ("empty", b"", 3),
    ("one", b"A", 3),
    ("short_text", b"hello world", 3),

    ("seq_a", b"abcdefgh" * 2, 3),
    ("seq_b", b"abcdefgh" * 4, 3),
    ("seq_c", b"ab" * 12, 3),
    ("seq_d", b"abcdefghij" * 3, 3),
    ("seq_e", b"abcdefgh" * 2 + b"XYZ" + b"abcdefgh" * 2, 3),
    ("repeat_text", b"abcabcabcabc" * 40, 3),
    ("lua_like", b"local function f(a,b) return a+b end " * 30, 3),
    ("zeros_1k", bytes(1024), 3),
    ("zeros_64k", bytes(65536), 3),
    ("counter", bytes(range(256)) * 8, 3),
    ("random_8k", bytes((i * 37 + 11) % 251 for i in range(8192)), 3),
    ("random_64k", bytes((i * 91 + 7) % 256 for i in range(65536)), 3),
    ("mixed", (b"the quick brown fox " * 200) + bytes(range(256)) * 40, 3),
    ("lvl1", b"compress me " * 500, 1),
    ("lvl9", b"compress me " * 500, 9),
    ("lvl19", b"compress me " * 500, 19),
    ("tiny_raw", b"x" * 3, 3),
    ("big_text", (b"abcdefghij" * 20000), 5),
    ("sparse", bytes(200000), 6),
    ("allbytes", bytes(range(256)) * 400, 7),
]

def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    for old in OUT.glob("*"):
        old.unlink()
    count = int(sys.argv[1]) if len(sys.argv) > 1 else len(CASES)
    for name, data, level in CASES[:count]:
        cctx = zstandard.ZstdCompressor(level=level)
        comp = cctx.compress(data)
        (OUT / (name + ".raw")).write_bytes(data)
        (OUT / (name + ".zst")).write_bytes(comp)
        ratio = (len(comp) / len(data)) if data else 0
        print("%-14s raw=%-8d zst=%-8d ratio=%.3f magic=%s" % (
            name, len(data), len(comp), ratio, comp[:4].hex()))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
