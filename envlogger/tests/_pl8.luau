local luau = require("@lune/luau")
local fs = require("@lune/fs")
local src = fs.readFile("C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_polsec1.lua")
local real = getfenv(0)
local calls = {}
local notes = {}
local function note(s) notes[#notes+1] = tostring(s):sub(1, 160) end

local lp: any = setmetatable({}, {
    __index = function(_, k)
        if k == "Kick" then
            return function(_s, msg) note("KICK " .. tostring(msg):sub(1, 100)); error("KICKED", 0) end
        end
        note("LP." .. tostring(k))
        return nil
    end,
})
local players = { LocalPlayer = lp }
local function svc(name)
    note("svc " .. tostring(name))
    if name == "HttpService" then
        return { JSONDecode = function(_s2, t) calls[#calls+1] = "JSONDecode " .. tostring(t):sub(1,80); return { a = 1, b = 1, c = "x" } end }
    end
    if name == "Players" then return players end
    return setmetatable({}, { __index = function(_, k) note("svc." .. tostring(name) .. "." .. tostring(k)); return nil end })
end
local gameObj: any = setmetatable({}, {
    __index = function(_, k)
        if k == "HttpGet" then return function(_s, u) calls[#calls+1] = "HttpGet " .. tostring(u):sub(1,120); return '{"a":1,"b":1,"c":"x"}' end end
        if k == "GetService" then return function(_s, n) return svc(n) end end
        note("game." .. tostring(k))
        return nil
    end,
})
local env: any = setmetatable({}, { __index = function(_, k) local v = real[k]; if v ~= nil then return v end; note("global " .. tostring(k)); return nil end })
env.script_key = "trial"
env.game = gameObj
env.workspace = setmetatable({}, { __index = function() return nil end })
env.request = function(a)
    local url = type(a) == "table" and (a.Url or a.url) or a
    calls[#calls + 1] = "request " .. tostring(url):sub(1, 120)
    return { StatusCode = 200, Success = true, Body = '{"a":1,"b":1,"c":"x"}', Headers = {} }
end
env.wait = function(t) note("wait " .. tostring(t)); error("STOPWAIT", 0) end
env.task = setmetatable({}, { __index = function(_t, k) note("task." .. tostring(k)); return function() note("taskcall"); error("STOPTASK", 0) end end })
env.warn = function(...) local p = {}; for i=1,select("#",...) do p[i]=tostring(select(i,...)) end; note("WARN " .. table.concat(p, " ")) end
env.print = function(...) local p = {}; for i=1,select("#",...) do p[i]=tostring(select(i,...)) end; note("PRINT " .. table.concat(p, " ")) end

local okL, fn = pcall(luau.load, src, { environment = env, injectGlobals = false, debugName = "entry" })
print("compiled:", okL)
if not okL then return end
local ok, err = xpcall(fn, function(e) return tostring(e) end)
print("ran:", ok, tostring(err):sub(1, 120))
print("--- calls:")
for _, c in ipairs(calls) do print("CALL", c) end
local start = math.max(1, #notes - 25)
for i = start, #notes do print("NOTE", notes[i]) end
