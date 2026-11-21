"""Extract one dispatch-loop tree from the (2) stage for a49_dispatch."""
import pathlib
import re
import sys

sys.path.insert(0, "tools")
from discover_anchors import enclosing_function

def loop_body(src, fetch):
    """Text from the fetch head through the end of its while loop."""
    i = src.find(fetch)
    if i < 0:
        raise SystemExit("fetch head missing: %r" % fetch)
    w = src.rfind("while true do", 0, i)

    depth = 0
    j = w
    quote = None
    toks = re.compile(r"[A-Za-z_][A-Za-z0-9_]*|\"|'")
    n = len(src)
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
        if ch == '"' or ch == "'":
            quote = ch
            j += 1
            continue
        m = toks.match(src, j)
        if not m:
            j += 1
            continue
        wd = m.group(0)
        j = m.end()
        if wd in ("while",):
            depth += 1
        elif wd in ("for", "if", "function", "repeat"):
            depth += 1
        elif wd in ("until",):
            depth -= 1
        elif wd == "end":
            depth -= 1
            if depth == 0:
                return src[i:j]
    raise SystemExit("unbalanced loop at %d" % w)

FETCHES = {
    "E": "local g=(m[E]);",
    "F": "local C=(m[F]);",
    "R": "local O=(m[r]);",
}

if __name__ == "__main__":
    work = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else pathlib.Path("tools/work_s2")
    loop = sys.argv[2] if len(sys.argv) > 2 else "F"
    src = (work / "stage.lua").read_text(encoding="utf-8")
    body = loop_body(src, FETCHES[loop])
    dest = work / ("a49_%s.lua" % loop)
    dest.write_text(body, encoding="utf-8")
    print("wrote", dest, len(body), "chars")
