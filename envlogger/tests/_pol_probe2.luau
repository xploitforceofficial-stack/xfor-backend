local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local path = process.env.POLFILE or "C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_polsec_a.lua"
local src = fs.readFile(path)
local real = getfenv(0)

local GATE = process.env.POLGATE or '{"a":0,"b":0,"c":"No fingerprint found"}'
local LOG = {}

local function log(s: string)
    if #LOG < 200 then LOG[#LOG + 1] = s end
end

local captured = {}
local bigStrings = {}

local function repr(v: any): string
    if type(v) == "string" then
        return string.format("%q", #v > 80 and (v:sub(1, 70) .. "...(" .. #v .. "b)") or v)
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
        __concat = function() return "" end,
        __eq = function() return false end,
    })
end

local waits = 0
local WAIT_LIMIT = tonumber(process.env.POLWAITS or "60")
local function spin(t: any)
    waits += 1
    log(string.format("WAIT #%d %s", waits, tostring(t)))
    if waits > WAIT_LIMIT then error("WAIT_SPIN", 0) end
    return t
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
env.warn = function(...) log("WARN " .. table.concat({ ... }, " ")) end
env.print = function(...) log("PRINT " .. table.concat({ ... }, " ")) end
env.task = bh("task")
env.task.wait = spin
env.wait = spin
env.tick = function() return os.clock() end
env.time = function() return os.time() end
env.getgenv = function() return env end
env.getfenv = function() return env end
env.setfenv = function(_, _e) return env end

env.loadstring = function(s: any, nm: any)
    if type(s) == "string" then
        captured[#captured + 1] = s
        log(string.format("LOADSTRING len=%d name=%s head=%q", #s, tostring(nm), s:sub(1, 140)))
    else
        log("LOADSTRING nonstring " .. type(s))
    end
    return function() return nil end
end
env.load = env.loadstring

local function gateBody(url: string): any
    if string.find(url, "getpolsec", 1, true) then
        log("GATE url=" .. url:sub(1, 160))
        log("GATE body=" .. GATE:sub(1, 160))
        return GATE
    end
    log("HTTP " .. url:sub(1, 160))
    return bh("http")
end

local function resp(url: string)
    local body = gateBody(url)
    if type(body) ~= "string" then body = GATE end
    return {
        StatusCode = 200, StatusMessage = "OK", Success = true,
        Body = body, Headers = { ["content-type"] = "application/json" },
    }
end
env.request = function(a: any, _b: any)
    local url = type(a) == "table" and (a.Url or a.url) or a
    return resp(tostring(url))
end
env.http_request = env.request
env.syn_request = env.request
env.HttpGet = function(u: any) return gateBody(tostring(u)) end

local gameObj: any = {}
local hs: any = {}
hs.JSONDecode = function(...)
    local serde = require("@lune/serde")
    local n = select("#", ...)
    local args = table.pack(...)
    local text = nil
    for i = 1, n do
        if type(args[i]) == "string" then text = args[i] end
    end
    local ok, v = pcall(function() return serde.decode("json", text) end)
    log(string.format("JSONDecode n=%d types=%s,%s text=%s -> c=%s",
        n, type(args[1]), type(args[2]), repr(text), tostring(ok and v and v.c)))
    log("TRACE " .. debug.traceback("", 2))
    return ok and v or {}
end
hs.JSONEncode = function(_self: any, v: any) return "{}" end
gameObj.HttpService = hs
gameObj.GetService = function(_self: any, n: any)
    log("GetService " .. tostring(n))
    if tostring(n) == "HttpService" then return hs end
    return bh("svc:" .. tostring(n))
end
gameObj.HttpGet = function(_self: any, u: any) return gateBody(tostring(u)) end
gameObj.PlaceId = 0
env.game = gameObj
env.workspace = bh("workspace")
env.Enum = bh("Enum")
env.Instance = setmetatable({}, { __index = function() return function() return bh("inst") end end })
env.instances = bh("instances")
env.syn = bh("syn")
env.cloneref = function(v) return v end
env.identifyexecutor = function() return "Roblox" end

local realConcat = real.table.concat
local wrappedTable = setmetatable({}, { __index = function(_, k)
    if k == "concat" then
        return function(t, sep)
            local out = realConcat(t, sep)
            if type(out) == "string" and #out > 4000 and #bigStrings < 30 then
                bigStrings[#bigStrings + 1] = out
                log(string.format("BIG concat len=%d head=%q", #out, out:sub(1, 90)))
            end
            return out
        end
    end
    return real.table[k]
end })
env.table = wrappedTable

local okLoad, fn = pcall(luau.load, src, { environment = env, injectGlobals = false })
if not okLoad then
    print("LOAD FAILED " .. tostring(fn):sub(1, 400))
    return
end
local t0 = os.clock()
local ok, err = xpcall(fn, function(e) return tostring(e) end)
print(string.format("ok=%s err=%s wall=%.2fs captured=%d big=%d waits=%d",
    tostring(ok), tostring(err):sub(1, 160), os.clock() - t0, #captured, #bigStrings, waits))
print("GATE=" .. GATE)
print("========== LOG ==========")
for _, l in ipairs(LOG) do print(l) end
for i, s in ipairs(captured) do
    print(string.format("--- captured[%d] len=%d ---", i, #s))
    print(s:sub(1, 400))
end
for i, s in ipairs(bigStrings) do
    print(string.format("--- big[%d] len=%d ---", i, #s))
    print(s:sub(1, 200))
end

local outDir = process.env.POLOUT
if outDir and #bigStrings > 0 then
    for i, s in ipairs(bigStrings) do
        fs.writeFile(outDir .. "/big" .. i .. ".bin", s)
    end
    print("wrote " .. #bigStrings .. " big strings to " .. outDir)
end
