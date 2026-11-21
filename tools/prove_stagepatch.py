"""Prove whether --stage-patch substitution actually applies.

Notes pushed inside the sandbox never reach the rendered dump, so "no note"
proves nothing. Replacing the stage body with an immediate error does: if the
run's behaviour changes, substitution applied; if not, it did not.

Usage:
  python tools/prove_stagepatch.py <stage.lua> <out.lua> <manifest.tsv>
"""
import pathlib
import sys

def main() -> int:
    src, out, manifest = (pathlib.Path(a) for a in sys.argv[1:4])
    text = src.read_text(encoding="utf-8", errors="replace")
    patched = 'error("[prove] patched stage in use", 0)\n' + text
    out.write_text(patched, encoding="utf-8")
    manifest.write_text("%d\t%s\n" % (len(text.encode("utf-8")), out.resolve().as_posix()),
                        encoding="utf-8")
    print("patched stage errors immediately; manifest key", len(text.encode("utf-8")))
    print("manifest:", manifest.resolve().as_posix())
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
