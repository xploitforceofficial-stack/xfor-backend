local fs = require("@lune/fs")

local HOST_PRINT = print
local HOST_DEBUG = debug
local HOST_OS = os
local HOST_LOAD = loadstring or load

local stageSrc = fs.readFile("tools/work_s2/stage_inst.lua")
local prog = fs.readFile("tools/work_s2/prog.bin")

local ENVLOG = {}
local LOGN = 0
local LOGCAP = 500000
local function trunc(v)
    local t = type(v)
    if t == "string" then
        if #v > 200 then
            return string.format("%q...", v:sub(1, 200))
        end
        return string.format("%q", v)
    elseif t == "number" or t == "boolean" or t == "nil" then
        return tostring(v)
    else
        local s = tostring(v)
        if #s > 60 then
            s = s:sub(1, 60)
        end
        return t .. ":" .. s
    end
end
local function logev(kind, path, args, extra)
    LOGN += 1
    if LOGN > LOGCAP then
        return
    end
    local parts = {}
    local n = math.min(#args, 12)
    for i = 1, n do
        parts[i] = trunc(args[i])
    end
    if extra ~= nil then
        parts[n + 1] = trunc(extra)
    end
    ENVLOG[LOGN] = kind .. "\t" .. path .. "\t" .. table.concat(parts, "\t")
end
local function proxy(path)
    local t = {}
    setmetatable(t, {
        __index = function(_, k)
            logev("get", path, { k })
            local child = proxy(path .. "." .. tostring(k))
            rawset(t, k, child)
            return child
        end,
        __call = function(_, ...)
            local args = table.pack(...)
            logev("call", path, args)
            return proxy(path .. "()")
        end,
        __newindex = function(_, k, v)
            logev("set", path .. "." .. tostring(k), {}, v)
            rawset(t, k, v)
        end,
        __tostring = function()
            return "proxy:" .. path
        end,

        __add = function(a, _) logev("op", path, { "add" }) return a end,
        __sub = function(a, _) logev("op", path, { "sub" }) return a end,
        __mul = function(a, _) logev("op", path, { "mul" }) return a end,
        __div = function(a, _) logev("op", path, { "div" }) return a end,
        __unm = function(a) logev("op", path, { "unm" }) return a end,
        __concat = function(a, _) logev("op", path, { "concat" }) return a end,
        __eq = function() return false end,
        __lt = function() logev("op", path, { "lt" }) return false end,
        __le = function() logev("op", path, { "le" }) return false end,
        __len = function() return 0 end,
    })
    return t
end

local MISN = 0
_G.LOGMISS = function(k)
    MISN += 1
    if MISN > 20000 then
        return
    end
    logev("miss", "global", { k })
end

local FACN = 0
_G.LOGFAC = function(k)
    FACN += 1
    if FACN > 5000 then
        return
    end
    logev("fac", "factory", { tostring(k):sub(1, 60) })
end

local function execfn(name, ret)
    return function(...)
        local args = table.pack(...)
        logev("call", name, args)
        return ret
    end
end
local taskStub = {}
do
    local budget = 1000
    taskStub.spawn = function(...)
        local args = table.pack(...)
        logev("call", "task.spawn", args)
        local f = args[1]
        if type(f) == "function" and budget > 0 then
            budget -= 1
            local ok, err = pcall(f, table.unpack(args, 2, args.n))
            if not ok then
                logev("error", "task.spawn", {}, err)
            end
        end
        return nil
    end
    taskStub.delay = taskStub.spawn
    taskStub.defer = taskStub.spawn
    taskStub.wait = function(...)
        local args = table.pack(...)
        logev("call", "task.wait", args)
        return 0
    end
    taskStub.cancel = function(...)
        logev("call", "task.cancel", table.pack(...))
        return nil
    end
    setmetatable(taskStub, {
        __index = function(_, k)
            logev("get", "task", { k })
            local child = proxy("task." .. tostring(k))
            rawset(taskStub, k, child)
            return child
        end,
        __tostring = function()
            return "proxy:task"
        end,
    })
end
local function loadstringStub(...)
    local args = table.pack(...)
    local src = args[1]
    logev("call", "loadstring", { type(src) == "string" and (#src .. " bytes: " .. src:sub(1, 200)) or src })
    if type(src) ~= "string" then
        return nil, "loadstring stub: bad source"
    end
    local fn, err = HOST_LOAD(src)
    if not fn then
        return nil, err
    end
    return fn
end
_G.DTS = {
    string = string, table = table, math = math, utf8 = utf8,
    bit32 = bit32, coroutine = coroutine, buffer = buffer,
    type = type, tostring = tostring, tonumber = tonumber,
    select = select, next = next, unpack = unpack or table.unpack,
    pcall = pcall, xpcall = xpcall, error = error, assert = assert,
    pairs = pairs, ipairs = ipairs,
    rawget = rawget, rawset = rawset, rawequal = rawequal,
    setmetatable = setmetatable, getmetatable = getmetatable,
    print = function(...)
        local args = table.pack(...)
        logev("call", "print", args)
        return HOST_PRINT(table.unpack(args, 1, args.n))
    end,
    warn = function(...)
        local args = table.pack(...)
        logev("call", "warn", args)
        return nil
    end,
    tick = function(...)
        logev("call", "tick", table.pack(...))
        return HOST_OS.clock()
    end,
    time = function(...)
        logev("call", "time", table.pack(...))
        return HOST_OS.clock()
    end,
    wait = function(...)
        local args = table.pack(...)
        logev("call", "wait", args)
        return 0
    end,
    spawn = taskStub.spawn, delay = taskStub.delay, defer = taskStub.defer,
    loadstring = loadstringStub, load = loadstringStub,
    require = execfn("require", proxy("require()")),
    task = taskStub,
    game = proxy("game"), workspace = proxy("workspace"),
    script = proxy("script"), plugin = proxy("plugin"),
    Instance = proxy("Instance"),
    Vector3 = proxy("Vector3"), Vector2 = proxy("Vector2"),
    CFrame = proxy("CFrame"),
    UDim = proxy("UDim"), UDim2 = proxy("UDim2"),
    Rect = proxy("Rect"), Color3 = proxy("Color3"),
    BrickColor = proxy("BrickColor"),
    NumberRange = proxy("NumberRange"),
    NumberSequence = proxy("NumberSequence"),
    ColorSequence = proxy("ColorSequence"),
    PhysicalProperties = proxy("PhysicalProperties"),
    Ray = proxy("Ray"), Region3 = proxy("Region3"),
    Random = proxy("Random"), TweenInfo = proxy("TweenInfo"),
    OverlapParams = proxy("OverlapParams"),
    RaycastParams = proxy("RaycastParams"),
    PathWaypoint = proxy("PathWaypoint"),
    Path2D = proxy("Path2D"),
    Font = proxy("Font"), Enum = proxy("Enum"),
    DateTime = proxy("DateTime"),
    os = proxy("os"), debug = proxy("debug"),
    settings = proxy("settings"),
    UserSettings = proxy("UserSettings"),

    islclosure = execfn("islclosure", true),
    iscclosure = execfn("iscclosure", false),
    isvararg = execfn("isvararg", false),
    isyieldable = execfn("isyieldable", true),
    identifyexecutor = execfn("identifyexecutor", "OmniDBF"),
    gethui = execfn("gethui", proxy("gethui()")),
    getrenv = execfn("getrenv", proxy("getrenv()")),
    getgenv = execfn("getgenv", proxy("getgenv()")),
    checkcaller = execfn("checkcaller", true),
    hookfunction = execfn("hookfunction", true),
    newcclosure = execfn("newcclosure", proxy("newcclosure()")),
}

local doLoad = HOST_LOAD

local function wrapclo(q, gid)
    if type(q) ~= "function" then
        return q
    end
    return function(...)
        local args = table.pack(...)
        local function call()
            return q(table.unpack(args, 1, args.n))
        end
        local function handler(e)
            return "CLO[" .. tostring(gid):sub(1, 60) .. "]: " .. tostring(e)
        end
        local r = table.pack(xpcall(call, handler))
        if not r[1] then
            error(r[2])
        end
        return table.unpack(r, 2, r.n)
    end
end
_G.WRAPCLO = wrapclo
local chunk = assert(doLoad(stageSrc, "=stage2"))
local ok, res, og, ov, ol, mklog, arr, ent, jl, zsh = xpcall(function()
    return chunk(buffer.fromstring(prog))
end, function(e)
    return tostring(e) .. "\n" .. HOST_DEBUG.traceback("", 2)
end)
if not ok then
    print("[run] post-run debug type=" .. type(HOST_DEBUG))
    local msg = tostring(res)
    local tb = HOST_DEBUG.traceback(msg, 2)

    local head = {}
    for line in string.gmatch(tb, "[^\n]+") do
        table.insert(head, line)
        if #head >= 14 then break end
    end
    print("[run] stage/program error:\n" .. table.concat(head, "\n"))
    og, ov, mklog, arr, ent, jl = og or {}, ov or {}, mklog or {}, arr or {}, ent or {}, jl or {}
else
    print("[run] returned type=" .. type(res))
    if type(res) == "function" then
        local r1, err1 = pcall(res)
        print("[run] program ok=" .. tostring(r1) .. " err=" .. tostring(err1))
    elseif type(res) == "table" then
        print("[run] res table; nothing further to call")
        local n = 0
        for _ in pairs(res) do
            n += 1
        end
        print("[run] res keys=" .. tostring(n))
    end
end
print("[run] dispatches=" .. #og)

print("[run] pre-fallback MKENTRY=" .. tostring(MKENTRY) .. " n=" .. tostring(MKENTRY and #MKENTRY))
print("[run] pre-fallback ok=" .. tostring(ok) .. " res=" .. tostring(res):sub(1,80))
print("[run] pre-fallback ent=" .. tostring(ent) .. " og=" .. tostring(og))
og = (type(OPG) == "table" and #OPG > 0) and OPG or {}
ov = (type(OPV) == "table" and #OPV > 0) and OPV or {}
ol = (type(OPL) == "table" and #OPL > 0) and OPL or {}
arr = (type(MKARR) == "table" and #MKARR > 0) and MKARR or {}
ent = (type(MKENTRY) == "table" and #MKENTRY > 0) and MKENTRY or {}
jl = (type(JLINK) == "table") and JLINK or {}
zsh = (type(ZSHOTV) == "table") and ZSHOTV or {}
print("[run] harvested dispatches=" .. #og .. " chains=" .. #arr)
print("[run] MKENTRY-direct=" .. tostring(MKENTRY and #MKENTRY))

local function cell(a, g)
    local ok, v = pcall(function()
        return a and a[g]
    end)
    if not ok or v == nil then
        return "-"
    end
    local ok2, s = pcall(tostring, v)
    if not ok2 then
        return "?"
    end
    return (s:gsub("[\t\r\n]", function(ch)
        if ch == "\t" then
            return "\\t"
        elseif ch == "\n" then
            return "\\n"
        end
        return "\\r"
    end))
end

local out3 = {}
for i = 1, #og do
    out3[i] = string.format("%s\t%s\t%s", tostring(og[i]), tostring(ov[i]),
        tostring((ol or {})[i]))
end
fs.writeFile("tools/work_s2/op.tsv", table.concat(out3, "\n") .. "\n")

local out4b = {}
for c = 1, #arr do
    local e = arr[c]
    out4b[c] = string.format("%d\t%s\t%d\t%s", c, tostring(e.hid), e.cnt, tostring(e.r))
end
fs.writeFile("tools/work_s2/a49arr.tsv", table.concat(out4b, "\n") .. "\n")

local out5 = {}
local n = 0
for c = 1, #arr do
    local e = arr[c]
    for g = 1, e.cnt do
        n += 1
        out5[n] = string.format(
            "%d\t%d\t%s\t%s\t%s\t%s\t%s\t%s\t%s",
            c, g,
            cell(e.m, g), cell(e.N, g), cell(e.h, g), cell(e.y, g),
            cell(e.f, g), cell(e.d, g), cell(e.n, g))
    end
end
fs.writeFile("tools/work_s2/chains.tsv", table.concat(out5, "\n") .. "\n")
print("[run] chain slots=" .. n .. " chains=" .. #arr)

local out6 = {}
if ent ~= nil then
    local m = 0
    for k = 1, #ent do
        local e = ent[k]
        for g = 1, e.cnt do
            m += 1
            out6[m] = string.format(
                "%s\t%d\t%s\t%s\t%s\t%s\t%s\t%s\t%s",
                tostring(e.hid), g,
                cell(e.m, g), cell(e.N, g), cell(e.h, g), cell(e.y, g),
                cell(e.f, g), cell(e.d, g), cell(e.n, g))
        end
    end
end
if #out6 > 0 then
    fs.writeFile("tools/work_s2/a49entry.tsv", table.concat(out6, "\n") .. "\n")
end
print("[run] entry chains=" .. (ent and #ent or 0))

local out8 = {}
if jl ~= nil then
    for k = 1, #jl do
        local e = jl[k]
        out8[k] = string.format("%s\t%s", tostring(e.f), tostring(e.b))
    end
end
if #out8 > 0 then
    fs.writeFile("tools/work_s2/jlink.tsv", table.concat(out8, "\n") .. "\n")
end
print("[run] jlinks=" .. #out8)

local out9 = {}
for i = 1, 80 do
    local e = zsh[i]
    if e ~= nil then
        out9[i] = string.format("%d\t%s\t%s", i, tostring(e.t),
            tostring(e.v):gsub("[\t\r\n]", "?"))
    end
end
if #out9 > 0 then
    fs.writeFile("tools/work_s2/zstate.tsv", table.concat(out9, "\n") .. "\n")
end
print("[run] zstate=" .. #out9)

if LOGN > 0 then
    local cap = math.min(LOGN, LOGCAP)
    local lines = {}
    for i = 1, cap do
        lines[i] = tostring(i) .. "\t" .. tostring(ENVLOG[i])
    end
    if LOGN > LOGCAP then
        lines[cap + 1] = "TRUNCATED at " .. tostring(LOGCAP)
    end
    fs.writeFile("tools/work_s2/envlog.tsv", table.concat(lines, "\n") .. "\n")
end
print("[run] envlog events=" .. tostring(LOGN))
do
    local fh = rawget(_G, "FACHITS")
    if type(fh) == "table" then
        print("[run] factory hits=" .. tostring(#fh))
        for i = 1, math.min(#fh, 5) do
            print("[run] fac[" .. tostring(i) .. "]=" .. tostring(fh[i]):sub(1, 60))
        end
    else
        print("[run] factory hits=0 (FACHITS " .. type(fh) .. ")")
    end
    local census = {}
    for k, v in pairs(_G) do
        if type(k) == "string" and (k == "OPG" or k == "FACHITS" or k == "DTS" or k == "MKENTRY" or k == "WRAPCLO" or k == "LOGMISS" or k == "LOGFAC" or k:sub(1, 2) == "__") then
            census[#census + 1] = k .. "=" .. type(v)
        end
    end
    table.sort(census)
    print("[run] _G census: " .. table.concat(census, " "))
end
print("[run] wrote work_s2 logs")
