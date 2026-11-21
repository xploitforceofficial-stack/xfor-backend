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
DST = WORK / "stage_inst.lua"

PREFIX = "OPG={};OPV={};OPL={};MKLOG={};MKARR={};MKSEEN={};MKENTRY={};JLINK={};ZSHOT=false;ENVDONE=false;FACHITS={};__DTSREF=(_G and _G.DTS);"

MAKER = "local f,y,m,N,h,d,n,a=k[1.0],k[4.0],k[2.0],k[3.0],k[5.0],k[6.0],k[10.0];"
MAKER_REPL = (
    MAKER
    + "table.insert(MKLOG,{#m});"
    + "if(not NTYPED)then NTYPED=true;print(\"NTYPES m=\"..type(m)..\" N=\"..type(N)"
    "..\" h=\"..type(h)..\" y=\"..type(y)..\" f=\"..type(f)..\" d=\"..type(d)"
    "..\" n=\"..type(n)..\" nm=\"..tostring(#m)..\" nn=\"..tostring(#n)"
    "..\" n1=\"..tostring(n[1]):sub(1,30));end;"
    + "table.insert(MKARR,{cnt=#m,hid=tostring(k),r=r,f=f,y=y,m=m,N=N,h=h,d=d,n=n});"
)

def yinj_tpl(env, flag):

    return (
        "if(rawget(" + env + ",\"UDim\")==nil)then "
        "if(type(_G.DTS)==\"table\" and type(" + env + ")==\"table\")then "
        "print(\"YINJ-FIRED\");"
        "for __k,__v in pairs(_G.DTS)do rawset(" + env + ",__k,__v); end; end;end;"
    )

ENV_TPL = ""

OPS = [
    ("local g=(m[E]);", "E", "g", "E", "t", "YINJ_E"),
    ("local C=(m[F]);", "F", "C", "F", "Y", "YINJ_F"),
    ("local O=(m[r]);", "r", "O", "R", "E", "YINJ_R"),
]

JENT_TPL = (
    "if(not MKSEEN[k])then MKSEEN[k]=true;"
    "table.insert(MKENTRY,{hid=tostring(k),cnt=#m,r=r,f=f,y=y,m=m,N=N,h=h,d=d,n=n});end;"
)

CLO = "q=z[51](g,H)"
CLO_REPL = (
    "q=z[51](g,H);table.insert(JLINK,{f=tostring(g),b=tostring(q)});"

    "if(type(H)==\"table\" and type(_G.DTS)==\"table\")then "
    "for __k,__v in pairs(_G.DTS)do "
    "if(rawget(H,__k)==nil)then rawset(H,__k,__v); end; end; end;"

    "if(type(_G.WRAPCLO)==\"function\")then q=_G.WRAPCLO(q,g); end"
)

SETENV = "d=setfenv"
SETENV_REPL = (
    "d=(function(__f,__e)"
    "if(type(__e)==\"table\" and type(_G.DTS)==\"table\")then "
    "for __k,__v in pairs(_G.DTS)do "
    "if(rawget(__e,__k)==nil)then rawset(__e,__k,__v); end; end; end;"
    "if(type(__e)==\"table\" and not rawget(__e,\"__dts_logged\"))then "
    "rawset(__e,\"__dts_logged\",true); "
    "print(\"SETENV fn=\"..tostring(__f):sub(1,40)"
    "..\" UDim=\"..tostring(rawget(__e,\"UDim\")):sub(1,20)"
    "..\" Instance=\"..tostring(rawget(__e,\"Instance\")):sub(1,20)"
    "..\" game=\"..tostring(rawget(__e,\"game\")):sub(1,20)"
    "..\" task=\"..tostring(rawget(__e,\"task\")):sub(1,20)"
    "..\" require=\"..tostring(rawget(__e,\"require\")):sub(1,20)); end;"
    "return setfenv(__f,__e); end)"
)

FACTORY = "(z)[51]=function(k,w,r)local O=(k[8]);r=(k[11]);"
FACTORY_REPL = (
    "(z)[51]=function(k,w,r)local O=(k[8]);r=(k[11]);"

    "do local __fh=(FACHITS);"
    "if(type(__fh)==\"table\")then __fh[#__fh+1]=tostring(k):sub(1,40); end; end;"
    "do local __dts=(__DTSREF);"
    "if(type(w)==\"table\" and type(__dts)==\"table\")then "
    "for __k,__v in pairs(__dts)do "
    "if(rawget(w,__k)==nil)then rawset(w,__k,__v); end; end; end; end;"

    "do local __gm=getmetatable; local __sm=setmetatable;"
    "if(type(w)==\"table\" and type(__gm)==\"function\" "
    "and type(__sm)==\"function\")then "
    "local __mt=__gm(w); "
    "if(__mt==nil)then "
    "__sm(w,{__index=function(__t,__k) "
    "local __lm=(_G and _G.LOGMISS); "
    "if(type(__lm)==\"function\")then __lm(__k); end; "
    "return nil; end}); "
    "elseif(type(__mt)==\"table\")then "
    "local __old=__mt.__index; "
    "__mt.__index=function(__t,__k) local __v=nil; "
    "if(type(__old)==\"function\")then __v=__old(__t,__k); "
    "elseif(type(__old)==\"table\")then __v=__old[__k]; end; "
    "if(__v==nil)then "
    "local __lm=(_G and _G.LOGMISS); "
    "if(type(__lm)==\"function\")then __lm(__k); end; end; "
    "return __v; end; end; end; end;"
)

TAIL = "}):H();"

TAIL_REPL = "}):H(),OPG,OPV,OPL,MKLOG,MKARR,MKENTRY,JLINK,ZSHOTV;"

def main() -> int:
    s = SRC.read_text(encoding="utf-8")
    if s.count(MAKER) != 1:
        raise SystemExit(f"maker anchor count = {s.count(MAKER)} (want 1)")
    for head, _, _, _, _, _ in OPS:
        if s.count(head) != 1:
            raise SystemExit(f"op anchor {head!r} count = {s.count(head)} (want 1)")
    if s.count(CLO) != 1:
        raise SystemExit(f"clo anchor count = {s.count(CLO)} (want 1)")
    if s.count(SETENV) != 1:
        raise SystemExit(f"setfenv anchor count = {s.count(SETENV)} (want 1)")
    if s.count(FACTORY) != 1:
        raise SystemExit(f"factory anchor count = {s.count(FACTORY)} (want 1)")
    if not s.endswith(TAIL):
        raise SystemExit(f"tail is {s[-len(TAIL):]!r} (want {TAIL!r})")
    out = PREFIX + s[: -len(TAIL)] + TAIL_REPL
    out = out.replace(MAKER, MAKER_REPL, 1)
    for head, pc, op, tag, env, flag in OPS:
        out = out.replace(
            head,
            head + f"OPG[#OPG+1]={pc};OPV[#OPV+1]={op};OPL[#OPL+1]=\"{tag}\";"
            + ENV_TPL
            + yinj_tpl(env, flag)

            + "if(not ZSHOT)then ZSHOT=true;ZSHOTV={};"
            + "for __i=1,80 do local __ok,__v=pcall(function() return z[__i]; end);"
            + "if(__ok)then ZSHOTV[__i]={t=type(__v),v=tostring(__v)}; end; end;end;"
            + JENT_TPL,
            1,
        )
    out = out.replace(CLO, CLO_REPL, 1)
    out = out.replace(SETENV, SETENV_REPL, 1)
    out = out.replace(FACTORY, FACTORY_REPL, 1)
    DST.write_text(out, encoding="utf-8")
    print(f"wrote {DST} ({len(out)} chars)")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
