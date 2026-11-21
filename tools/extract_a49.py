"""Extract A[49] (the VM dispatch loop) from the single-line stage."""
import pathlib
import re

STAGE = pathlib.Path(__file__).resolve().parent / "work" / "stage147.lua"
OUT = pathlib.Path(__file__).resolve().parent / "work" / "a49_full.lua"

def extract(s: str, start: int) -> str:
    """Return the function value starting at `start`, block-keyword matched."""
    j = start
    quote = None
    depth = 0
    tokens = re.compile(r"[A-Za-z_][A-Za-z0-9_]*|\"|'")
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
        m = tokens.match(s, j)
        if not m:
            j += 1
            continue
        w = m.group(0)
        j = m.end()
        if w in ("function", "if", "while", "for", "repeat"):
            depth += 1
        elif w == "do":

            pass
        elif w == "until":
            depth -= 1
        elif w == "end":
            depth -= 1
            if depth == 0:
                return s[start:j]
    raise ValueError("unbalanced")

def main() -> int:
    s = STAGE.read_text(encoding="utf-8")
    i = s.index("[49]=function") + 1
    src = extract(s, i)
    OUT.write_text(src, encoding="utf-8")
    print(f"A[49] {len(src)} chars, span {i}..{i + len(src)}")
    print("P occurrences:", len(re.findall(r"\bP\b", src)))
    print(src[:700])
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
