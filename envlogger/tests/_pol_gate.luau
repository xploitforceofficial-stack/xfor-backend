local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local path = process.env.POLFILE or "C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_polsec_a.lua"
local src = fs.readFile(path)
local real = getfenv(0)

local LOG: { string } = {}
local function log(s: string)
    if #LOG < 400 then LOG[#LOG + 1] = s end
end

local captured: { string } = {}

local function repr(v: any): string
    local t = typeof(v)
    if t == "string" then
        return string.format("%q", v:sub(1, 120))
    end
    return tostring(v)
end

local function bh(name: string): any
    return setmetatable({}, {
        __index = function(_, k)
            log(string.format("bh index %s.%s", name, tostring(k)))
            return bh(name .. "." .. tostring(k))
        end,
        __call = function(_, ...)
            log(string.format("bh call %s(%s)", name, repr((...))))
            return bh(name .. "()")
        end,
        __tostring = function() return name end,
        __len = function() return 0 end,
        __add = function() return 0 end,
        __sub = function() return 0 end,
        __lt = function() return false end,
        __le = function() return false end,
        __eq = function() return false end,
        __concat = function() return "" end,
    })
end

local env: any = setmetatable({}, {
    __index = function(_, k)
        local rv = real[k]
        if rv ~= nil then return rv end
        log("missing global: " .. tostring(k))
        return bh(tostring(k))
    end,
})

env.script_key = process.env.POLKEY or "trial"
env.warn = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = repr((select(i, ...))) end
    log("WARN: " .. table.concat(parts, " "))
end
env.print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = repr((select(i, ...))) end
    log("PRINT: " .. table.concat(parts, " "))
end
env.loadstring = function(s: any, nm: any)
    if type(s) == "string" then
        captured[#captured + 1] = s
        log(string.format("LOADSTRING len=%d name=%s", #s, tostring(nm)))
    else
        log(string.format("LOADSTRING nonstring %s", type(s)))
    end
    return function() return nil end
end
env.load = env.loadstring

local httpLog = function(which: string)
    return function(...)
        local a = { ... }
        local url = tostring(a[1])
        log(string.format("%s url=%s opts=%s", which, url:sub(1, 160), tostring(a[2]):sub(1, 120)))
        return bh(which)
    end
end
env.request = httpLog("request")
env.http_request = httpLog("http_request")
env.syn_request = httpLog("syn_request")
env.HttpGet = httpLog("HttpGet")

local function jsonDecode(s: any)
    log("JSONDecode " .. repr(s))
    return bh("json")
end
local function jsonEncode(v: any)
    log("JSONEncode " .. repr(v))
    return "{}"
end

local gameObj: any = bh("game")
gameObj.GetService = function(_, n: any)
    log("game:GetService " .. tostring(n))
    return bh("svc:" .. tostring(n))
end
gameObj.HttpGet = httpLog("game:HttpGet")
env.game = gameObj

local svc = bh("HttpService")
svc.JSONDecode = jsonDecode
env.HttpService = svc

local okLoad, fn = pcall(luau.load, src, { environment = env, injectGlobals = false })
if not okLoad then
    print("LOAD FAILED", tostring(fn):sub(1, 400))
    return
end
local t0 = os.clock()
local ok = xpcall(fn, function(e) return tostring(e) end)
print(string.format("native ok=%s wall=%.2fs captured=%d log=%d", tostring(ok), os.clock() - t0, #captured, #LOG))
print("========== LOG ==========")
for _, l in ipairs(LOG) do print(l) end
for i, s in ipairs(captured) do
    print(string.format("--- captured[%d] len=%d", i, #s))
    print(s:sub(1, 300))
end
