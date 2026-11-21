local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local path = process.env.POLFILE or "C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_polsec1k.lua"
local src = fs.readFile(path)
local real = getfenv(0)
local LIMIT = tonumber(process.env.POLLIMIT or "600")

local LOG: { string } = {}
local function log(s: string)
    if #LOG < LIMIT then LOG[#LOG + 1] = s end
end
local captured: { string } = {}
local waits = 0

local function repr(v: any): string
    if typeof(v) == "string" then
        return string.format("%q", #v > 100 and (v:sub(1, 90) .. "…(" .. #v .. "b)") or v)
    end
    return tostring(v)
end

local function bh(name: string): any
    return setmetatable({}, {
        __index = function(_, k) return bh(name .. "." .. tostring(k)) end,
        __call = function(_, ...) return bh(name .. "[call]") end,
        __tostring = function() return name end,
        __len = function() return 0 end,
        __add = function() return 0 end, __sub = function() return 0 end,
        __mul = function() return 0 end, __div = function() return 0 end,
        __mod = function() return 0 end, __pow = function() return 0 end,
        __unm = function() return 0 end,
        __eq = function() return false end, __lt = function() return false end,
        __le = function() return false end, __concat = function() return "" end,
        __metatable = "locked",
    })
end

local env: any = setmetatable({}, {
    __index = function(_, k)
        local rv = real[k]
        if rv ~= nil then return rv end
        log("GLOBAL(read) " .. tostring(k))
        return bh(tostring(k))
    end,
})

env.script_key = process.env.POLKEY or "trial"

local function fmt(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = repr((select(i, ...))) end
    return table.concat(parts, " ")
end
env.warn = function(...) log("WARN: " .. fmt(...)) end
env.print = function(...) log("PRINT: " .. fmt(...)) end
env.task = bh("task")
env.task.wait = function(t) waits += 1; if waits > 4 then error("WAIT_SPIN", 0) end; return t end
env.wait = function(t) waits += 1; if waits > 4 then error("WAIT_SPIN", 0) end; return t end
env.tick = function() return os.clock() end
env.time = function() return os.time() end
env.getgenv = function() return env end
env.getfenv = function() return env end
env.setfenv = function(_, e) return env end

env.loadstring = function(s: any, nm: any)
    if type(s) == "string" then
        captured[#captured + 1] = s
        log(string.format("LOADSTRING len=%d name=%s head=%s", #s, tostring(nm), string.format("%q", s:sub(1, 120))))
    else
        log("LOADSTRING nonstring " .. typeof(s))
    end
    return function() return nil end
end
env.load = env.loadstring

local function http(which: string)
    return function(...)
        local a = { ... }
        log(string.format("%s url=%s", which, tostring(a[1]):sub(1, 200)))
        return bh(which)
    end
end
env.request = http("request")
env.http_request = http("http_request")
env.syn_request = http("syn_request")
env.HttpGet = http("HttpGet")
env.HTTPGet = http("HTTPGet")

local gameObj: any = bh("game")
gameObj.GetService = function(_, n: any) log("game:GetService " .. tostring(n)); return bh("svc:" .. tostring(n)) end
gameObj.HttpGet = http("game:HttpGet")
gameObj.PlaceId = 0
env.game = gameObj
env.workspace = bh("workspace")
env.Enum = bh("Enum")
env.Instance = setmetatable({}, { __index = function() return function() return bh("inst") end end })
env.instances = bh("instances")
env.syn = bh("syn")
env.cloneref = function(v) return v end
env.firetouch = function() end
env.is_sirhurt_closure = function() return false end
env.identifyexecutor = function() return "Roblox" end

local function jsonDecode(s: any)
    log("JSONDecode " .. repr(s))
    return bh("json")
end
gameObj.HttpService = setmetatable({}, { __index = function(_, k)
    if k == "JSONDecode" then return jsonDecode end
    if k == "JSONEncode" then return function(v) log("JSONEncode " .. repr(v)); return "{}" end end
    return bh("HttpService." .. tostring(k))
end })
gameObj.GetService = function(_, n: any)
    log("game:GetService " .. tostring(n))
    if tostring(n) == "HttpService" then return gameObj.HttpService end
    return bh("svc:" .. tostring(n))
end

local okLoad, fn = pcall(luau.load, src, { environment = env, injectGlobals = false })
if not okLoad then print("LOAD FAILED", tostring(fn):sub(1, 400)); return end
local t0 = os.clock()
local ok, err = xpcall(fn, function(e) return tostring(e) end)
print(string.format("native ok=%s err=%s wall=%.2fs captured=%d waits=%d log=%d",
    tostring(ok), tostring(err):sub(1, 120), os.clock() - t0, #captured, waits, #LOG))
print("========== LOG ==========")
for _, l in ipairs(LOG) do print(l) end
for i, s in ipairs(captured) do
    print(string.format("--- captured[%d] len=%d", i, #s))
    print(s:sub(1, 600))
end
