"""Instrument a Luraph v14 stage for program capture (g6/GY/A49/J/op hooks).

The stage is a single line, so this is a plain string patch. Anchors default
to the (4)-build strings; pass --anchors-json from discover_anchors.py for a
new build (see discover_anchors.py --verify for the method's ground truth).

Usage: python tools/patch_stage.py [--src IN] [--dst OUT] [--anchors JSON]
"""
import argparse
import json
import pathlib

WORK = pathlib.Path(__file__).resolve().parent / "work"
SRC = WORK / "stage147.lua"
DST = WORK / "stage147_inst.lua"

PREFIX = "G6LOG={};GYLOG={};OPG={};OPV={};A49LOG={};A49ARR={};A49SEEN={};A49ENTRY={};UPLOG={};JLINK={};"
PREFIX += (
    "local function __ESC(s) local x=tostring(s);"
    " x=x:gsub(\"\\\\\",\"\\\\\\\\\"); x=x:gsub(\"\\t\",\"\\\\t\");"
    " x=x:gsub(\"\\n\",\"\\\\n\"); x=x:gsub(\"\\r\",\"\\\\r\"); return x; end;"
)
PREFIX += (
    "local function UPLOG_EMIT(H,j)"
    " local hh=tostring(H); local ui=0;"
    " local function rec(tbl,prefix,depth)"
    " if(depth>1 or ui>160)then return; end;"
    " local ok,keys=pcall(function() local r={}; for k,_ in pairs(tbl)do"
    " if(#r>64)then break; end; r[#r+1]=k; end; return r; end);"
    " if(not ok)then return; end;"
    " for i=1,#keys do local k=keys[i];"
    " if(ui>160)then return; end;"
    " local ok2,v=pcall(function() return tbl[k]; end);"
    " if(ok2)then local tp=type(v); local path=prefix..tostring(k); ui+=1;"
    " if(tp==\"number\" or tp==\"string\" or tp==\"boolean\")then"
    " table.insert(UPLOG,{h=hh,path=path,tp=tp,v=__ESC(v)});"
    " elseif(tp==\"table\")then"
    " table.insert(UPLOG,{h=hh,path=path,tp=\"table\",v=tostring(v)});"
    " local ok3,b1=pcall(function() return v[1]; end);"
    " local ok4,b3=pcall(function() return v[3]; end);"
    " if(ok3 and ok4 and type(b1)==\"table\" and type(b3)==\"number\")then"
    " local ok5,bv=pcall(function() return b1[b3]; end);"
    " if(ok5)then table.insert(UPLOG,{h=hh,path=path..\"[box]\",tp=type(bv),v=__ESC(bv)}); end; end;"
    " rec(v,path..\".\",depth+1);"
    " elseif(tp==\"function\")then"
    " table.insert(UPLOG,{h=hh,path=path,tp=\"function\",v=tostring(v)});"
    " else table.insert(UPLOG,{h=hh,path=path,tp=tp,v=__ESC(v)}); end;"
    " end; end; end;"
    " if(type(j)==\"table\")then rec(j,\"\",0); end;"
    " end;"
)
ANCHOR = "Q=nil;return H,A,Y,Q,c,F,C;end"
REPL = "Q=nil;table.insert(G6LOG,{n=#G6LOG,l3=l[3],H=H,A=A,Y=Y,c=c});return H,A,Y,Q,c,F,C;end"
GY_ANCHOR = "n,W,d,Z,T,J,G=Y:WY(H,T,l,v,f,d,J,n,A,t,Z,W,F,D,G,w,O,z);"
GY_REPL = GY_ANCHOR + "table.insert(GYLOG,{w=w,K=W,op=d,Z=Z,T=T,J=J,G=G,H=t});"
OP_ANCHOR = "local P=(t[G]);"
OP_REPL = "local P=(t[G]);OPG[#OPG+1]=G;OPV[#OPV+1]=P;"
A49_ANCHOR = "H[7.0];J=function(...)"
A49_REPL = (
    "H[7.0];table.insert(A49LOG,{#t,t[1],t[2],t[3]});"
    "table.insert(A49ARR,{n=#t,h=tostring(H),t=t,i=i,w=w,D=D,f=f,O=O,z=z});J=function(...)"
)

J_ANCHOR = "J=function(...)local d,G,W,T,Z,n,g,e,h,q,o,K,b,a,S,L,U=A[46](v),1.0,1.0,1.0,(A[37]());local v,I,X,E,N,r,u=0.0;"
J_REPL = (
    J_ANCHOR
    + "if(not A49SEEN[H])then A49SEEN[H]=true;"
    + "table.insert(A49ENTRY,{h=tostring(H),n=#t,t=t,i=i,w=w,D=D,f=f,O=O,z=z});"
    + "UPLOG_EMIT(H,j);end;"
)

CLO_ANCHOR = "b=A[49](K,g)"
CLO_REPL = "b=A[49](K,g);table.insert(JLINK,{f=tostring(K),b=tostring(b)})"
TAIL = "}):S();"
TAIL_REPL = "}):S(),G6LOG,GYLOG,OPG,OPV,A49LOG,A49ARR,A49ENTRY,UPLOG,JLINK;"

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=str(SRC))
    ap.add_argument("--dst", default=str(DST))
    ap.add_argument("--anchors", default=None,
                    help="JSON {g6,gy,op,a49,jent,clo} anchor strings for this build")
    args = ap.parse_args()
    src_path, dst_path = pathlib.Path(args.src), pathlib.Path(args.dst)
    ov = {}
    if args.anchors:
        ov = json.loads(pathlib.Path(args.anchors).read_text(encoding="utf-8"))
    A = {
        "g6": ov.get("g6", ANCHOR),
        "gy": ov.get("gy", GY_ANCHOR),
        "op": ov.get("op", OP_ANCHOR),
        "a49": ov.get("a49", A49_ANCHOR),
        "jent": ov.get("jent", J_ANCHOR),
        "clo": ov.get("clo", CLO_ANCHOR),
    }
    s = src_path.read_text(encoding="utf-8")
    for name in ("g6", "gy", "op", "a49", "jent", "clo"):
        n = s.count(A[name])

        want = 1
        if n != want:
            raise SystemExit(f"{name} anchor count = {n} (want {want}): {A[name][:70]!r}")
    if not s.endswith(TAIL):
        raise SystemExit(f"tail is {s[-len(TAIL):]!r} (want {TAIL!r})")
    out = PREFIX + s[: -len(TAIL)] + TAIL_REPL
    out = (
        out.replace(A["g6"], REPL, 1)
        .replace(A["gy"], GY_REPL, 1)
        .replace(A["op"], OP_REPL, 1)
        .replace(A["a49"], A49_REPL, 1)
        .replace(A["jent"], J_REPL, 1)
        .replace(A["clo"], CLO_REPL, 1)
    )
    dst_path.write_text(out, encoding="utf-8")
    print(f"wrote {dst_path} ({len(out)} chars)")

if __name__ == "__main__":
    raise SystemExit(main())
