"""
Luraph v14 loop-env backfill (second pass).

The program reads globals through its loop env tables (`Y["UDim2"]`,
`Y["Instance"]`, ...), but the stage leaves those tables empty: in Roblox
they fall through to the real globals, here they are just empty tables, so
the first `.new` on a nil entry dies (`attempt to index nil with 'new'`).

The fix mirrors what the real environment provides: copy every name the
program can name from the running chunk's own globals into the loop env,
once (sentinel-guarded). Only stage-internal tables are written - no new
sandbox globals appear - and only names that actually resolve are copied,
so this degrades to a no-op wherever the chunk env is restricted.
"""
import re

NAMES = (
    "Instance", "Vector3", "Vector2", "CFrame", "UDim", "UDim2", "Rect",
    "Color3", "BrickColor", "NumberRange", "NumberSequence", "ColorSequence",
    "PhysicalProperties", "Ray", "Region3", "Random", "TweenInfo",
    "OverlapParams", "RaycastParams", "PathWaypoint", "Path2D", "Font",
    "Enum", "DateTime", "game", "workspace", "script", "plugin",
    "task", "require", "tick", "time", "string", "table", "math", "utf8",
    "os", "coroutine", "bit32", "buffer", "type", "typeof", "tostring",
    "tonumber", "select", "next", "unpack", "pcall", "xpcall", "error",
    "assert", "print", "warn", "pairs", "ipairs", "rawget", "rawset",
    "rawequal", "setmetatable", "getmetatable", "loadstring", "debug",
    "settings", "islclosure", "iscclosure", "isvararg", "isyieldable",
    "identifyexecutor", "gethui", "getrenv", "getgenv", "checkcaller",
    "spawn", "wait", "delay", "defer",
)

FETCH_HEADS = (
    ("local C=(m[F]);", "Y"),
)

def backfill(text):
    """Copy chunk-env globals into loop env tables. Returns (text, nfilled).

    `text` comes back unchanged when an anchor is missing - never broken.
    """
    names_lua = "{" + ",".join('"%s"' % n for n in NAMES) + "}"
    n = 0
    for head, env in FETCH_HEADS:
        if text.count(head) != 1:
            continue
        merge = (
            head
            + "do if rawget(" + env + ",\"UDim2\")==nil then "
            + "local _e=getfenv(0);"
            + "if type(_e)==\"table\" then "
            + "local _ns=" + names_lua + ";"
            + "for _i=1,#_ns do local _n=_ns[_i];local _v=_e[_n];"
            + "if _v~=nil and rawget(" + env + ",_n)==nil then "
            + "rawset(" + env + ",_n,_v); end; end; end; end; end;"
        )
        text = text.replace(head, merge, 1)
        n += 1
    return text, n
