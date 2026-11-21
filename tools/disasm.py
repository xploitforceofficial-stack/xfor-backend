"""Disassemble the 192 chains: opcode leaf + concrete operands per slot.

chains.tsv has one row per (chain, slot) with the opcode and the six operand
arrays; opcodes/<P>.lua has the leaf code A[49] runs for that opcode. Splicing
them turns `d[D[G]] = d[w[G]][z[G]]` into `d[15] = d[15][band]`.

Usage:  python tools/disasm.py [chain ...]   (no args = every chain)
"""
import pathlib
import re
import sys

WORK = pathlib.Path(__file__).resolve().parent / "work"
FIELDS = ("t", "i", "w", "D", "f", "O", "z")

def load_slots():
    slots = {}
    order = {}
    for line in (WORK / "chains.tsv").read_text(encoding="utf-8", errors="replace").splitlines():
        parts = line.split("\t")
        if len(parts) != 9:
            continue
        c, g = int(parts[0]), int(parts[1])
        vals = {f: parts[2 + k].replace("\\t", "\t").replace("\\n", "\n") for k, f in enumerate(FIELDS)}
        slots[(c, g)] = vals
        order.setdefault(c, []).append(g)
    return slots, order

def leaf(P: int) -> list:
    f = WORK / "opcodes" / f"{P:03d}.lua"
    if not f.exists():
        return [f"-- no leaf for opcode {P}"]
    return [
        ln for ln in f.read_text(encoding="utf-8").splitlines()
        if ln.strip() and not ln.startswith("-- opcode") and not ln.startswith("-- ")
    ]

def substitute(text: str, vals: dict) -> str:
    def rep(m):
        name = m.group(1)
        if name not in vals:
            return m.group(0)
        v = vals[name]
        if v == "-":
            return "nil"
        if re.fullmatch(r"-?\d+", v):
            return v
        if re.fullmatch(r"-?\d+\.\d+", v):
            return v
        if v.startswith("table:"):
            return v
        return f'"{v}"'

    return re.sub(r"\b(" + "|".join(FIELDS) + r")\[G\]", rep, text)

def main() -> int:
    slots, order = load_slots()
    want = [int(x) for x in sys.argv[1:]] or sorted(order)
    out = []
    for c in want:
        if c not in order:
            print(f"no chain {c}", file=sys.stderr)
            continue
        out.append(f"===== chain {c} ({len(order[c])} slots)")
        for g in sorted(order[c]):
            vals = slots[(c, g)]
            P = int(vals["t"]) if vals["t"].isdigit() else -1
            body = [ln for ln in leaf(P) if ln.strip()]
            if not body:
                continue
            ops = " ".join(f"{f}={vals[f]}" for f in ("i", "w", "D", "f", "O", "z") if vals[f] != "-")
            out.append(f"-- [{c}:{g}] op={P} {ops}")
            for ln in body:
                out.append("    " + substitute(ln.strip(), vals))
    text = "\n".join(out) + "\n"
    dest = WORK / "disasm.txt"
    dest.write_text(text, encoding="utf-8")
    print(f"wrote {dest} ({len(text)} chars, {len(out)} lines)")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
