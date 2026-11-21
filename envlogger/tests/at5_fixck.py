"""Re-sign tests/at5_fixture.lua after editing its guarded body.

The fixture verifies its own embedded source with DJB2 mod 2^32. Luau's lexer
skips the newline immediately after `[==[`, so the guarded value starts at the
byte after that newline and ends before the newline that precedes `]==]`.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PATH = os.path.join(HERE, "at5_fixture.lua")

def djb2(data: bytes) -> int:
    h = 5381
    for b in data:
        h = (h * 33 + b) % 4294967296
    return h

def main() -> int:
    src = open(PATH, encoding="utf-8", newline="").read()

    m = re.search(r"\[==\[\n(.*?)\]==\]", src, re.S)
    if not m:
        print("guarded body not found")
        return 1
    body = m.group(1).encode("utf-8")
    ck = djb2(body)
    new, n = re.subn(r"checksum\(guardedSource\) ~= \d+",
                     f"checksum(guardedSource) ~= {ck}", src)
    if n != 1:
        print("checksum site not found")
        return 1
    if new != src:
        open(PATH, "w", encoding="utf-8", newline="").write(new)
        print(f"re-signed: {ck} (body {len(body)} bytes)")
    else:
        print(f"checksum already correct: {ck} (body {len(body)} bytes)")
    return 0

if __name__ == "__main__":
    sys.exit(main())
