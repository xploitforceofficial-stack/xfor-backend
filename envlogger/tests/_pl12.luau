local luau = require("@lune/luau")
local fs = require("@lune/fs")

local src = fs.readFile("C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_polsec1.lua")
local real = getfenv(0)
local reqs: { string } = {}
local notes: { string } = {}
local function note(s) notes[#notes + 1] = tostring(s):sub(1, 120) end

local function dumpTbl(t: any): string
    if type(t) ~= "table" then return tostring(t) end
    local parts: { string } = {}
    for k, v in pairs(t) do
        parts[#parts + 1] = tostring(k) .. "=" .. (type(v) == "table" and dumpTbl(v) or tostring(v):sub(1, 100))
    end
    return "{" .. table.concat(parts, ", ") .. "}"
end

local players: any = setmetatable({}, { __index = function(_, k)
    if k == "LocalPlayer" then
        return setmetatable({}, { __index = function(_t2, k2)
            if k2 == "Kick" then return function(_s, msg) note("KICK " .. tostring(msg):sub(1, 80)); error("KICKED", 0) end end
            note("LP." .. tostring(k2)); return nil
        end })
    end
    note("PL." .. tostring(k)); return nil
end })

local env: any = setmetatable({}, { __index = function(_, k)
    local v = real[k]
    if v ~= nil then return v end
    note("G?" .. tostring(k))
    return nil
end })
env.script_key = "trial"
env.gethwid = function() return "HWID-TEST-1234" end
env.getHwid = env.gethwid
env.get_hwid = env.gethwid
env.getgenv = function() return {} end
env.identifyexecutor = function() return "TestExec" end
env.getexecutorname = function() return "TestExec" end
env.syn = { request = env.request, get_key = function() return "SYNKEY123" end }
env.krnl_request = env.request
env.game = setmetatable({}, { __index = function(_, k)
    if k == "HttpGet" then return function(_s, u, cache)
        reqs[#reqs + 1] = "HttpGet url=" .. tostring(u) .. " cache=" .. tostring(cache)
        return '{"a":0,"b":0,"c":"No fingerprint found"}'
    end end
    if k == "GetService" then return function(_s, n)
        if n == "HttpService" then
            return {
                JSONDecode = function(_s2, t)
                    local a = t:match('"a"%s*:%s*([^,}]+)')
                    local b = t:match('"b"%s*:%s*([^,}]+)')
                    local c = t:match('"c"%s*:%s*"([^"]*)"')
                    local out: any = {}
                    if a then
                        if a == "null" then out.a = nil else out.a = tonumber(a) or a end
                    end
                    if b then
                        if b == "null" then out.b = nil else out.b = tonumber(b) or b end
                    end
                    out.c = c
                    return out
                end,
            }
        end
        if n == "Players" then return players end
        note("svc " .. tostring(n)); return setmetatable({}, {})
    end end
    note("game." .. tostring(k)); return nil
end })
env.workspace = {}
env.request = function(a)
    reqs[#reqs + 1] = "request " .. dumpTbl(a)
    return { StatusCode = 200, Success = true, Body = '{"a":0,"b":0,"c":"No fingerprint found"}', Headers = {} }
end
env.http_request = env.request
env.syn = { request = env.request }
env.wait = function(t) note("wait " .. tostring(t)); error("STOPWAIT", 0) end
env.task = setmetatable({}, { __index = function() return function() note("taskcall"); error("STOPTASK", 0) end end })
env.warn = function(...) local p = {}; for i = 1, select("#", ...) do p[i] = tostring(select(i, ...)) end note("WARN " .. table.concat(p, " ")) end
env.print = function(...) local p = {}; for i = 1, select("#", ...) do p[i] = tostring(select(i, ...)) end note("PRINT " .. table.concat(p, " ")) end

local okL, fn = pcall(luau.load, src, { environment = env, injectGlobals = false, debugName = "e" })
if not okL then print("COMPILE-FAIL", tostring(fn):sub(1, 200)); return end
local ok, err = xpcall(fn, function(e) return tostring(e) end)
print("ran:", ok, tostring(err):sub(1, 60))
print("--- outgoing requests:")
for _, r in ipairs(reqs) do print(r:sub(1, 600)) end
print("--- notes:")
for _, n2 in ipairs(notes) do print("  ", n2) end
