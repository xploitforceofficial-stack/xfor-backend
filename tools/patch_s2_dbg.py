"""Instrument the (2)-build stage (work_s2/stage.lua) for program capture.

Same method as patch_stage.py but for this build's names/shapes (discovered
structurally; see discover_anchors.py):
  maker  `local f,y,m,N,h,d,n,a=k[1.0],...` -> MKLOG (descriptor arrays)
  op     3 loop-head fetches -> OPG/OPV (pc + opcode per loop)
  jent   after each fetch head -> MKENTRY (post-patch arrays, first call)
  clo    `q=z[51](g,H)` -> JLINK (descriptor -> closure identity)

No g6/GY hooks: the program buffer is pre-decoded (see zstd_layers.py), so
the loader phase is skipped entirely.

Usage: python tools/patch_s2.py
"""

import pathlib

WORK = pathlib.Path(__file__).resolve().parent / "work_s2"
SRC = WORK / "stage.lua"
DST = WORK / "stage_dbg.lua"

PREFIX = "OPG={};OPV={};MKLOG={};MKARR={};MKSEEN={};MKENTRY={};JLINK={};"

MAKER = "local f,y,m,N,h,d,n,a=k[1.0],k[4.0],k[2.0],k[3.0],k[5.0],k[6.0],k[10.0];"
MAKER_REPL = (
    MAKER
    + "table.insert(MKLOG,{#m});"
    + "table.insert(MKARR,{cnt=#m,hid=tostring(k),r=r,f=f,y=y,m=m,N=N,h=h,d=d,n=n});"
)

OPS = [
    ("local g=(m[E]);", "E", "g"),
    ("local C=(m[F]);", "F", "C"),
    ("local O=(m[r]);", "r", "O"),
]

JENT_TPL = (
    "table.insert(MKENTRY,{kid=type(k),mm=type(m)});"
)

CLO = "q=z[51](g,H)"
CLO_REPL = "q=z[51](g,H);table.insert(JLINK,{f=tostring(g),b=tostring(q)})"

TAIL = "}):H();"
TAIL_REPL = "}):H(),OPG,OPV,MKLOG,MKARR,MKENTRY,JLINK;"

def main() -> int:
    s = SRC.read_text(encoding="utf-8")
    if s.count(MAKER) != 1:
        raise SystemExit(f"maker anchor count = {s.count(MAKER)} (want 1)")
    for head, _, _ in OPS:
        if s.count(head) != 1:
            raise SystemExit(f"op anchor {head!r} count = {s.count(head)} (want 1)")
    if s.count(CLO) != 1:
        raise SystemExit(f"clo anchor count = {s.count(CLO)} (want 1)")
    if not s.endswith(TAIL):
        raise SystemExit(f"tail is {s[-len(TAIL):]!r} (want {TAIL!r})")
    out = PREFIX + s[: -len(TAIL)] + TAIL_REPL
    out = out.replace(MAKER, MAKER_REPL, 1)
    for head, pc, op in OPS:
        out = out.replace(
            head,
            head + f"OPG[#OPG+1]={pc};OPV[#OPV+1]={op};"
            + JENT_TPL,
            1,
        )
    out = out.replace(CLO, CLO_REPL, 1)
    DST.write_text(out, encoding="utf-8")
    print(f"wrote {DST} ({len(out)} chars)")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
