"""Extract named functions from the single-line stage for reading."""
import pathlib
import re
import sys

STAGE = pathlib.Path(__file__).resolve().parent / "work" / "stage147.lua"

TOKENS = re.compile(r"[A-Za-z_][A-Za-z0-9_]*|\"|'")

def extract_function(s: str, start: int) -> str:
    """start points at the `function` keyword. Returns through the matching end."""
    j = start
    quote = None
    depth = 0
    while j < len(s):
        ch = s[j]
        if quote:
            if ch == "\\":
                j += 2
                continue
            if ch == quote:
                quote = None
            j += 1
            continue
        if ch in ('"', "'"):
            quote = ch
            j += 1
            continue
        m = TOKENS.match(s, j)
        if not m:
            j += 1
            continue
        w = m.group(0)
        j = m.end()
        if w in ("function", "if", "while", "for", "repeat"):
            depth += 1
        elif w == "until":
            depth -= 1
        elif w == "end":
            depth -= 1
            if depth == 0:
                return s[start:j]
    raise ValueError("unbalanced")

def find(s: str, name: str) -> str:
    m = re.search(r"(?<![A-Za-z0-9_])" + re.escape(name) + r"=function", s)
    if not m:
        raise KeyError(name)
    return extract_function(s, s.index("function", m.start()))

def main() -> int:
    s = STAGE.read_text(encoding="utf-8")
    names = sys.argv[1:] or [
        "dY", "mY", "cY", "tY", "KY", "EY", "XY", "jY", "BY", "GY", "WY",
        "g6", "w6", "y6", "Y6", "aY", "sY", "nY", "i6", "f6",
    ]
    outdir = pathlib.Path(__file__).resolve().parent / "work" / "funcs"
    outdir.mkdir(exist_ok=True)
    for n in names:
        try:
            body = find(s, n)
        except KeyError:
            print(f"{n}: not found")
            continue
        (outdir / f"{n}.lua").write_text(body, encoding="utf-8")
        print(f"{n}: {len(body)} chars")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
