"""Rewrite the debug.info value-resolution preamble in src/env/roblox.luau.

The file is CRLF; build the replacement in CRLF form and assert exactly one hit.
"""
import io
import sys

PATH = "src/env/roblox.luau"

OLD = """\t\t\toptions = options or "sln"\r
\t\t\t-- dual-nature wrappers (callable tables tagged typeName="function") must\r
\t\t\t-- report like the builtin they alias: resolve to the aliased name\r
\t\t\t-- instance/datatype methods arrive Spy-wrapped; resolve the inner fn so\r
\t\t\t-- the name registry (WaitForChild, Clone, Connect...) still matches\r
\t\t\tlocal nameTarget: any = target\r
\t\t\tif Spy.is(target) then\r
\t\t\t\tlocal inner = Spy.unwrap(target)\r
\t\t\t\tif inner ~= nil then\r
\t\t\t\t\tnameTarget = inner\r
\t\t\t\tend\r
\t\t\tend\r
\t\t\tlocal dualAlias: string? = nil\r
\t\t\tdo\r
\t\t\t\tlocal descriptor = Symbol.get(target)\r
\t\t\t\tlocal detail = descriptor and descriptor.detail\r
\t\t\t\tif detail and detail.dualNature and detail.aliasOf then\r
\t\t\t\t\tdualAlias = detail.aliasOf\r
\t\t\t\tend\r
\t\t\tend\r
"""

NEW = """\t\t\toptions = options or "sln"\r
\t\t\t-- What the script holds is often a stand-in: a Spy proxy for\r
\t\t\t-- instance/datatype members, a dual-nature callable tagged\r
\t\t\t-- typeName="function", or the instrumentation's __wrapFunc table.\r
\t\t\t-- Resolve the value they stand for so source/name/line stay faithful.\r
\t\t\tlocal original: any = target\r
\t\t\tlocal lookup: any = target\r
\t\t\tfor _ = 1, 4 do\r
\t\t\t\tlocal moved = false\r
\t\t\t\tif Spy.is(lookup) then\r
\t\t\t\t\tlocal inner = Spy.unwrap(lookup)\r
\t\t\t\t\tif inner ~= nil and inner ~= lookup then\r
\t\t\t\t\t\tlookup = inner\r
\t\t\t\t\t\tmoved = true\r
\t\t\t\t\tend\r
\t\t\t\tend\r
\t\t\t\tlocal descriptor = Symbol.get(lookup)\r
\t\t\t\tlocal detail = descriptor and descriptor.detail\r
\t\t\t\tif detail ~= nil and type(detail.wrappedFunction) == "function" then\r
\t\t\t\t\tlookup = detail.wrappedFunction\r
\t\t\t\t\tmoved = true\r
\t\t\t\tend\r
\t\t\t\tif not moved then\r
\t\t\t\t\tbreak\r
\t\t\t\tend\r
\t\t\tend\r
\t\t\tlocal nameTarget: any = lookup\r
\t\t\t-- dual-nature callables and engine closures carry a canonical C name in\r
\t\t\t-- the fidelity registry (WaitForChild, Clone, byte, getmetatable...)\r
\t\t\tlocal dualAlias: string? = nil\r
\t\t\tdo\r
\t\t\t\tlocal FidelityMod = require("./fidelity")\r
\t\t\t\tlocal descriptor = Symbol.get(target)\r
\t\t\t\tlocal detail = descriptor and descriptor.detail\r
\t\t\t\tif detail ~= nil and detail.dualNature and type(detail.aliasOf) == "string" then\r
\t\t\t\t\tdualAlias = detail.aliasOf\r
\t\t\t\tend\r
\t\t\t\tif dualAlias == nil then\r
\t\t\t\t\tdualAlias = FidelityMod.cname(lookup)\r
\t\t\t\tend\r
\t\t\t\tif dualAlias == nil then\r
\t\t\t\t\tdualAlias = FidelityMod.cname(target)\r
\t\t\t\tend\r
\t\t\tend\r
"""

DBG_START = '\t\t\tif _G.__FUHD_DBG_INFO then\n'
DBG_END = '\t\t\tend\n'

def main() -> int:
    src = open(PATH, encoding="utf-8", newline="").read()
    if OLD not in src:
        print("OLD preamble not found")
        return 1
    src = src.replace(OLD, NEW, 1)

    start = src.find(DBG_START)
    if start != -1:
        end = src.find(DBG_END, start)
        if end == -1:
            print("debug block end not found")
            return 1
        src = src[:start] + src[end + len(DBG_END):]
        print("removed debug print block")
    else:

        start = src.find(DBG_START.replace("\n", "\r\n"))
        if start != -1:
            end = src.find(DBG_END.replace("\n", "\r\n"), start)
            src = src[:start] + src[end + len(DBG_END.replace("\n", "\r\n")):]
            print("removed debug print block (crlf)")

    old_f = '\t\t\t\t\t\tvalues[#values + 1] = target\r\n'
    if old_f in src:
        src = src.replace(old_f, '\t\t\t\t\t\tvalues[#values + 1] = original\r\n', 1)
        print("f flag now returns the original value")
    else:
        print("WARN: f-flag line not found")

    open(PATH, "w", encoding="utf-8", newline="").write(src)
    print("rewritten")
    return 0

if __name__ == "__main__":
    sys.exit(main())
