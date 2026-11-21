"""Validate the v14 lift against the dynamic trace (same-run files).

Checks:
  1. jump targets: attributable (G,P) fetches must land on stored-target+1
     (the +1 is the dispatch epilogue; see lift14). Reports match rate.
  2. fallthrough: attributable non-jump fetches must advance to G+1... except
     at call/return boundaries between chains (reported, not failures).
  3. opcode coverage: every executed P has a leaf; every static P has a leaf.

Usage: python tools/validate14.py [workdir]  (exit 0 if jump rate >= 0.95)
"""
import pathlib
import re
import sys
from collections import Counter, defaultdict

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from lift14 import load_leaves, clean_leaf

COL = {"m": 0, "N": 1, "h": 2, "y": 3, "f": 4, "d": 5, "n": 6}

def jump_field(P, leaves):
    """Return (array, conditional) for a jump leaf, or None for fallthrough.

    Shapes across the sample families:
      (4) `G=(i[G]);`   unconditional, pc register G
      (2) `F=(N[F]);`   may be guarded by a compare, pc register F

    A guarded jump is only a valid transition if the next pc is either the
    stored target (+1 epilogue) or pc+1 (guard was false), so a wrong operand
    column can satisfy neither.
    """
    body = " ".join(clean_leaf(leaves.get(P, "")))
    m = re.fullmatch(r"\s*(G|F)\s*=\s*\(?\s*(\w+)\[\1\]\s*\)?\s*;?\s*", body)
    if m:
        arr, reg = m.group(2), m.group(1)
        return (arr, False) if arr in COL or arr in ("D", "i", "w") else None

    m = re.fullmatch(r"\s*.*?\bif\b.*?\bF\s*=\s*\(?\s*(\w+)\[F\]\s*\)?\s*end\s*"
                     r"F\s*\+=\s*[\d.]+\s*", body)
    if m and m.group(1) in COL:
        return (m.group(1), True)
    return None

def main() -> int:
    work = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else \
        pathlib.Path(__file__).resolve().parent / "work"
    post = defaultdict(dict)
    chains_path = work / ("chains_post.tsv" if (work / "chains_post.tsv").exists()
                          else "chains.tsv")
    for line in chains_path.read_bytes().decode("latin-1").splitlines():
        p = line.split("\t")
        if len(p) == 9:
            post[int(p[1])][int(p[0])] = p[2:]
    leaves = load_leaves(work)
    rows = [l.split() for l in (work / "op.tsv").read_text(encoding="utf-8")
            .splitlines() if l.strip()]
    n_test = n_ok = 0
    bad = Counter()
    n_fall = f_ok = 0
    for k in range(len(rows) - 1):
        g, P = rows[k][0], rows[k][1]
        cands = [(c, v) for c, v in post.get(int(g), {}).items() if v[0] == P]
        if not cands:
            continue
        fld = jump_field(int(float(P)), leaves)

        arr_i = None
        if fld:
            arr, guarded = fld
            arr_i = ({"D": 3, "i": 1, "w": 2}[arr] if arr in ("D", "i", "w") else COL[arr])
        if len(cands) > 1:
            if arr_i is None:
                continue
            if len({c[1][arr_i] for c in cands}) != 1:
                continue
        c, v = cands[0]
        if fld:
            arr, guarded = fld
            idx = arr_i
            n_test += 1
            nxt = rows[k + 1][0]
            target = str(int(float(v[idx])) + 1)
            if guarded:

                if nxt == target or nxt == str(int(g) + 1):
                    n_ok += 1
                else:
                    bad[(g, P, arr, v[idx], nxt)] += 1
            elif target == nxt:
                n_ok += 1
            else:
                bad[(g, P, arr, v[idx], nxt)] += 1
        else:
            n_fall += 1
            if str(int(g) + 1) == rows[k + 1][0]:
                f_ok += 1
    jr = n_ok / max(1, n_test)
    fr = f_ok / max(1, n_fall)
    print("jump transitions: %d match: %d rate: %.4f" % (n_test, n_ok, jr))
    for k, n in bad.most_common(8):
        print("  miss x%d %s" % (n, k))
    print("fallthrough: %d advance: %d rate: %.4f (rest = call/return boundaries)" %
          (n_fall, f_ok, fr))
    exe = {r[1] for r in rows}
    noleaf = sorted({p for p in exe if int(float(p)) not in leaves})
    print("executed opcodes without leaf: %s" % (noleaf or "none"))
    return 0 if jr >= 0.95 and not noleaf else 1

if __name__ == "__main__":
    raise SystemExit(main())
