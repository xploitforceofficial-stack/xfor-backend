local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local path = process.env.POLFILE or "C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_polsec_a.lua"
local src = fs.readFile(path)
local real = getfenv(0)

local LOG: { string } = {}
local function log(s: string) if #LOG < 500 then LOG[#LOG + 1] = s end end
local captured: { string } = {}
local waits = 0

local PK: string? = nil

local function repr(v: any): string
    if typeof(v) == "string" then
        return string.format("%q", #v > 100 and (v:sub(1, 90) .. "…(" .. #v .. "b)") or v)
    elseif typeof(v) == "table" then
        local parts = {}
        for i, x in ipairs(v) do parts[i] = repr(x); if i > 8 then parts[i] = "…" break end end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return tostring(v)
end

local function trap(name: string, mode: string): any
    return setmetatable({}, {
        __index = function(_, k)
            local key = tostring(k)
            log(string.format("TRAP %s.%s", name, key))
            if mode == "json" then

                if key == "c" then
                    local v = process.env.POLC or "PK"
                    if v == "NIL" then return nil end
                    if v == "TABLE" then return { "a", "b", payload = "x" } end
                    if v == "LONG" then return string.rep("A", 12000) end
                    if v == "NUM" then return os.time() + 86400 * 30 end
                    if v == "BOOLTRUE" then return true end
                    if v == "PK" then return PK or "<pk-not-captured>" end
                    return v
                end
                local successish = { success = true, valid = true, ok = true, status = true,
                    expired = false, banned = false, key = true, script = true, code = true,
                    hwid = false, expiry = os.time() + 86400 * 30, expires = os.time() + 86400 * 30 }
                if successish[key] ~= nil then return successish[key] end
                return trap(name .. "." .. key, mode)
            end
            return trap(name .. "." .. key, mode)
        end,
        __call = function(_, ...) log("TRAP call " .. name .. "(" .. repr((...)) .. ")"); return trap(name .. "()", mode) end,
        __tostring = function() return name end,
        __len = function() return 0 end, __concat = function() return "" end,
        __add = function() return 0 end, __eq = function() return false end,
        __lt = function() return false end, __le = function() return false end,
        __metatable = "locked",
    })
end

local env: any = setmetatable({}, {
    __index = function(_, k)
        local rv = real[k]
        if rv ~= nil then return rv end
        log("GLOBAL(read) " .. tostring(k))
        return trap(tostring(k), "any")
    end,
})
env.script_key = process.env.POLKEY or "trial"

local CONCATS: { string } = {}
local BIGGEST: { string } = {}
local realConcat = table.concat
local realChar = string.char
local function track(s: string)
	if #s < 2 or #s > 2000000 then return end
	CONCATS[#CONCATS + 1] = s

	if #BIGGEST < 24 then
		BIGGEST[#BIGGEST + 1] = s
		table.sort(BIGGEST, function(a, b) return #a > #b end)
	elseif #s > #BIGGEST[#BIGGEST] then
		BIGGEST[#BIGGEST] = s
		table.sort(BIGGEST, function(a, b) return #a > #b end)
	end
end
local concatSpy = function(tbl: any, sep: any?)
	local ok, res = pcall(realConcat, tbl, sep)
	if ok and type(res) == "string" then track(res) end
	if ok then return res else return realConcat(tbl) end
end
local charSpy = function(...)
	local ok, res = pcall(realChar, ...)
	if ok and type(res) == "string" then track(res) end
	if ok then return res else return realChar(...) end
end
env.string = setmetatable({}, { __index = function(_, k: any)
	if k == "char" then return charSpy end
	return (real :: any).string[k]
end })
env.table = setmetatable({}, { __index = function(_, k: any)
	if k == "concat" then return concatSpy end
	return (real :: any).table[k]
end })

local function fmt(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = repr((select(i, ...))) end
    return table.concat(parts, " ")
end
env.warn = function(...) log("WARN: " .. fmt(...)) end
env.print = function(...) log("PRINT: " .. fmt(...)) end
env.task = trap("task", "any")
local function waitish(t) waits += 1; if waits > 6 then error("WAIT_SPIN", 0) end; return t end
env.task.wait = waitish
env.wait = waitish
env.tick = os.clock
env.time = os.time
env.getgenv = function() return env end
env.getfenv = function() return env end
env.setfenv = function(_, _e) return env end
env.loadstring = function(s: any, nm: any)
    if type(s) == "string" then
        captured[#captured + 1] = s
        log(string.format("LOADSTRING len=%d name=%s head=%s", #s, tostring(nm), string.format("%q", s:sub(1, 140))))
    else log("LOADSTRING nonstring " .. typeof(s)) end
    return function() return nil end
end
env.load = env.loadstring

local RESPONSE_BODY = '{"success":true,"valid":true,"ok":true,"status":true,"expired":false,"banned":false,"key":true,"script":true,"code":true,"expiry":' .. (os.time() + 86400 * 30) .. ',"expires":' .. (os.time() + 86400 * 30) .. ',"message":"ok"}'

local function http(which: string)
    return function(...)
        local a = { ... }
        local first = a[1]
        local url: string
        if typeof(first) == "table" then
            local fields = {}
            for k, v in pairs(first) do fields[#fields + 1] = tostring(k) .. "=" .. repr(v) end
            url = tostring(first.Url or first.url or "")
            log(string.format("%s(body) {%s}", which, table.concat(fields, ", ")))
        else
            url = tostring(first)
            log(string.format("%s url=%s", which, url))
        end
        local pk = url:match("pk=([%w%d]+)")
        if pk then
            PK = pk
            log("PK captured: " .. pk)
        end
        return { StatusCode = 200, StatusMessage = "OK", Body = RESPONSE_BODY,
                 Success = true, Headers = {}, body = RESPONSE_BODY }
    end
end
env.request = http("request")
env.http_request = http("http_request")
env.syn_request = http("syn_request")
env.HttpGet = http("HttpGet")
env.HTTPGet = http("HTTPGet")

local gameObj: any = trap("game", "any")
local httpService: any = { JSONDecode = function(_, s: any)
    log("JSONDecode " .. repr(s))
    return trap("json", "json")
end, JSONEncode = function(_, v) log("JSONEncode " .. repr(v)); return "{}" end }
gameObj.HttpService = httpService
gameObj.HttpGet = http("game:HttpGet")
gameObj.GetService = function(_, n: any)
    log("game:GetService " .. tostring(n))
    if tostring(n) == "HttpService" then return httpService end
    return trap("svc:" .. tostring(n), "any")
end
env.game = gameObj
env.workspace = trap("workspace", "any")
env.Enum = trap("Enum", "any")
env.Instance = setmetatable({}, { __index = function() return function() return trap("inst", "any") end end })
env.instances = trap("instances", "any")
env.syn = trap("syn", "any")
env.cloneref = function(v) return v end
env.identifyexecutor = function() return "Roblox" end

local okLoad, fn = pcall(luau.load, src, { environment = env, injectGlobals = false })
if not okLoad then print("LOAD FAILED", tostring(fn):sub(1, 400)); return end
local t0 = os.clock()
local ok, err = xpcall(fn, function(e) return tostring(e) end)print(string.format("native ok=%s err=%s wall=%.2fs captured=%d waits=%d log=%d concats=%d",
	tostring(ok), tostring(err):sub(1, 120), os.clock() - t0, #captured, waits, #LOG, #CONCATS))
print("========== BIGGEST decoded artifacts ==========")
for i, s in ipairs(BIGGEST) do
	print(string.format("#%d len=%d", i, #s))
	print("  head: " .. string.format("%q", s:sub(1, 200)))
end
print("========== LOG ==========")
for _, l in ipairs(LOG) do print(l) end
for i, s in ipairs(captured) do
    print(string.format("--- captured[%d] len=%d", i, #s))
    print(s:sub(1, 800))
end
