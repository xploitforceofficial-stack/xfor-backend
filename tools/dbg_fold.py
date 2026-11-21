"""Dump the raw fold for one opcode (before clean()) to see what was dropped."""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import a49_dispatch as D

def main() -> int:
    P = int(sys.argv[1])
    src = D.A49.read_text(encoding="utf-8")
    anchor = "local P=(t[G]);"
    body = src[src.index(anchor) + len(anchor) :]
    notes: list = []
    D.TRACE.clear()
    out = D.fold(body, P, notes)
    print("--- P tests taken:")
    for cond, taken in D.TRACE:
        print(f"    {'THEN' if taken else 'ELSE'}  {cond}")
    print("--- notes:")
    for n in dict.fromkeys(notes):
        print("   ", n)
    print("--- raw statements:", len(out))
    for i, s in enumerate(out):
        print(f"{i:3d}| {s[:600]}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
