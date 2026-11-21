"""Discover patch anchors structurally in a Luraph v14 stage file.

patch_stage.py hardcodes the (4)-build anchor STRINGS (obfuscated names differ
per build). This tool finds the same SITES by shape so a new build of the same
Luraph version can be instrumented without a manual pass:

  g6    instruction-header reader: `...;return A,B,C,D,E,F,G;end` (7 values)
  gy    operand folder: a method call with 10+ args `=X:Y(a,b,...)`
  op    dispatch fetch: `local P=(t[G]);` shape (any names)
  a49   main dispatch: `[N];J=function(...)` (descriptor index + maker)
  jent  J prologue: regs init `=A(v),1.0,1.0,1.0,(A37())` + `local ...=0.0;`
  clo   closure creation: `b=A[49](K,g)` shape (any names)

Usage:
  python tools/discover_anchors.py <stage.lua> [--verify]
--verify asserts the discovered sites equal the known (4)-build anchors
(ground truth for the discovery patterns themselves).

Output: JSON {name: {count, sites: [matched text...]}} to stdout.
"""
import collections
import json
import pathlib
import re
import sys

PATTERNS = {

    "g6": re.compile(r"return\s+[A-Za-z_]\w*,[A-Za-z_]\w*,[A-Za-z_]\w*,"
                     r"[A-Za-z_]\w*,[A-Za-z_]\w*,[A-Za-z_]\w*,[A-Za-z_]\w*;end"),

    "gy": re.compile(r"=[A-Za-z_]\w*:[A-Za-z_]\w*\((?:[^();]*,){9,}[^();]*\);"),

    "op": re.compile(r"local\s+[A-Za-z_]\w*\s*=\s*\(\s*[A-Za-z_]\w*\s*\[\s*[A-Za-z_]\w*\s*\]\s*\);"),

    "a49": re.compile(r"[A-Za-z_]\w*\[\d+(?:\.\d+)?\];[A-Za-z_]\w*=function\(\.\.\.\)"),

    "jent": re.compile(r"=[A-Za-z_]\w*(?:\[\d+\])?\(\w+\),1\.0,1\.0,1\.0,"
                       r"\(\w+\[\d+\]\(\)\);local\s+[A-Za-z_]\w*(?:,[A-Za-z_]\w*)*=0\.0;"),

    "clo": re.compile(r"[A-Za-z_]\w*=[A-Za-z_]\w*\[\d+\]\([A-Za-z_]\w*,[A-Za-z_]\w*\)"),
}

READER_CALL = re.compile(r"([A-Za-z_]\w*)\[(\d+)\]\(\)")

def enclosing_function(src, pos):
    """Span of the `=function...end` block containing pos (balanced)."""
    start = src.rfind("=function(", 0, pos)
    if start < 0:
        return None
    i = src.index("(", start)
    depth = 1
    j = i
    quote = None
    n = len(src)
    toks = re.compile(r"[A-Za-z_][A-Za-z0-9_]*|\"|'")
    while j < n:
        ch = src[j]
        if quote:
            if ch == "\\":
                j += 2
                continue
            if ch == quote:
                quote = None
            j += 1
            continue
        if ch in ("\"", "'"):
            quote = ch
            j += 1
            continue
        m = toks.match(src, j)
        if not m:
            j += 1
            continue
        w = m.group(0)
        j = m.end()
        if w in ("function", "if", "while", "for", "repeat"):
            depth += 1
        elif w == "do":
            pass
        elif w in ("until",):
            depth -= 1
        elif w == "end":
            depth -= 1
            if depth == 0:
                return (start, j)
    return None

def disambiguate(src, found):
    """Apply contextual rules; returns {name: chosen_site_or_None}."""
    pick = {}

    a49s = found["a49"]["sites"]
    pick["a49"] = a49s[0] if len(a49s) == 1 else None

    ops = found["op"]["sites"]
    if len(ops) == 1:
        pick["op"] = ops[0]
    else:
        pick["op"] = None
        if pick["a49"]:
            apos = src.find(pick["a49"])
            cands = []
            for o in ops:
                p = src.find(o)
                while p >= 0:
                    if p > apos:
                        cands.append((p, o))
                        break
                    p = src.find(o, p + 1)
            if cands:
                cands.sort()
                pick["op"] = cands[0][1]

    g6s = found["g6"]["sites"]
    scored = []
    for g in g6s:
        p = src.find(g)
        span = enclosing_function(src, p)
        if not span:
            continue
        body = src[span[0]:span[1]]
        readers = collections.Counter(m.group(0) for m in READER_CALL.finditer(body))
        best = max(readers.values()) if readers else 0
        scored.append((best >= 3, best, g))
    scored.sort(reverse=True)
    pick["g6"] = scored[0][2] if scored and scored[0][0] else None

    gys = found["gy"]["sites"]
    scored = []
    for g in gys:
        m = re.match(r"=([A-Za-z_]\w*(?:,[A-Za-z_]\w*)*)=?", g)
        lhs = g.split("=")[0]
        n_targets = len([x for x in lhs.split(",") if x.strip()])
        n_args = g.count(",")
        scored.append((n_args, n_targets == 7, g))
    scored.sort(reverse=True)
    pick["gy"] = scored[0][2] if scored else None

    clos = found["clo"]["sites"]
    if len(clos) == 1:
        pick["clo"] = clos[0]
    else:
        near = []
        for c in clos:
            p = src.find(c)
            ctx = src[max(0, p - 120):p]
            near.append(("[10]" in ctx, c))
        near.sort(reverse=True)
        pick["clo"] = near[0][1] if near and near[0][0] else None

    jents = found["jent"]["sites"]
    pick["jent"] = jents[0] if len(jents) == 1 else None
    return pick

KNOWN = {
    "g6": "Q=nil;return H,A,Y,Q,c,F,C;end",
    "gy": "n,W,d,Z,T,J,G=Y:WY(H,T,l,v,f,d,J,n,A,t,Z,W,F,D,G,w,O,z);",
    "op": "local P=(t[G]);",
    "a49": "H[7.0];J=function(...)",
}

def discover(src):
    out = {}
    for name, pat in PATTERNS.items():
        sites = [m.group(0) for m in pat.finditer(src)]
        out[name] = {"count": len(sites), "sites": sites[:6]}
    return out

def main() -> int:
    verify = "--verify" in sys.argv
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not args:
        print("usage: discover_anchors.py <stage.lua> [--verify]", file=sys.stderr)
        return 2
    src = pathlib.Path(args[0]).read_text(encoding="utf-8")
    found = discover(src)
    if verify:
        ok = True
        pick = disambiguate(src, found)

        checks = {
            "op": "local P=(t[G]);",
            "a49": "H[7.0];J=function(...)",
        }
        for name, want in checks.items():
            got = pick.get(name)
            if got == want:
                print("OK   %-4s rediscovered: %r" % (name, got))
            else:
                ok = False
                print("FAIL %-4s want %r, picked %r" % (name, want, got))
        g6pick = pick.get("g6") or ""
        if g6pick.endswith("return H,A,Y,Q,c,F,C;end"):
            print("OK   g6   rediscovered: ...%r" % g6pick[-32:])
        else:
            ok = False
            print("FAIL g6   picked %r" % (g6pick[-60:] if g6pick else None))
        gypick = pick.get("gy") or ""
        if "Y:WY(H,T,l,v,f,d,J,n,A,t,Z,W,F,D,G,w,O,z)" in gypick:
            print("OK   gy   rediscovered: %r" % gypick[-60:])
        else:
            ok = False
            print("FAIL gy   picked %r" % (gypick[-60:] if gypick else None))
        for name in ("jent", "clo"):
            print("INFO %-4s picked: %r" % (name, (pick.get(name) or "")[:90]))
        return 0 if ok else 1
    print(json.dumps(found, indent=1)[:4000])
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
