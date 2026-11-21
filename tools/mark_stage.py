"""Prepend an unconditional marker to a patched stage, to prove substitution.

`--stage-patch` swaps a stage by byte length. If the patched text never runs,
either the length key did not match or the code inside it is unreachable; the
two are indistinguishable without a marker that cannot be skipped.

Usage: python tools/mark_stage.py <patched-stage.lua>
"""
import pathlib
import sys

MARK = '-- PATCHMARK v14\nprint("[patch] substituted stage in use")\n'

def main() -> int:
    p = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else None
    if p is None or not p.exists():
        print(__doc__)
        return 2
    t = p.read_text(encoding="utf-8")
    if t.startswith("-- PATCHMARK"):
        print("already marked:", p)
        return 0
    p.write_text(MARK + t, encoding="utf-8")
    print("marked:", p)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
