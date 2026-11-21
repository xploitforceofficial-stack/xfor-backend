local luau = require("@lune/luau")
local fs = require("@lune/fs")
local src = fs.readFile("C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_polsec1.lua")
local real = getfenv(0)

local function runVariant(name, body)
    local calls, notes = {}, {}
    local function note(s) notes[#notes+1] = tostring(s):sub(1, 140) end
    local players: any = setmetatable({}, { __index = function(_, k)
        if k == "LocalPlayer" then
            return setmetatable({}, { __index = function(_t2, k2)
                if k2 == "Kick" then return function(_s, msg) note("KICK " .. tostring(msg):sub(1, 60)); error("KICKED", 0) end end
                note("LP." .. tostring(k2)); return nil
            end })
        end
        note("PL." .. tostring(k)); return nil
    end })
    local env: any = setmetatable({}, { __index = function(_, k)
        local v = real[k]; if v ~= nil then return v end; note("G?" .. tostring(k)); return nil
    end })
    env.script_key = "trial"
    env.game = setmetatable({}, { __index = function(_, k)
        if k == "HttpGet" then return function(_s, u) calls[#calls+1] = "HttpGet " .. tostring(u):sub(40, 90); return body end end
        if k == "GetService" then return function(_s, n)
            if n == "HttpService" then return { JSONDecode = function(_s2, t) calls[#calls+1] = "JD"; return t end } end
            if n == "Players" then return players end
            note("svc " .. tostring(n)); return setmetatable({}, {})
        end end
        note("game." .. tostring(k)); return nil
    end })
    env.workspace = {}
    env.request = function(a) calls[#calls+1] = "req"; return { StatusCode = 200, Success = true, Body = body, Headers = {} } end
    env.wait = function(t) note("wait " .. tostring(t)); error("STOPWAIT", 0) end
    env.task = setmetatable({}, { __index = function() return function() note("taskcall"); error("STOPTASK", 0) end end })
    env.warn = function(...) local p = {}; for i=1,select("#",...) do p[i]=tostring(select(i,...)) end; note("WARN " .. table.concat(p, " ")) end
    env.print = function(...) local p = {}; for i=1,select("#",...) do p[i]=tostring(select(i,...)) end; note("PRINT " .. table.concat(p, " ")) end

    local okL, fn = pcall(luau.load, src, { environment = env, injectGlobals = false, debugName = "e" })
    if not okL then print(name, "COMPILE-FAIL"); return end
    local ok, err = xpcall(fn, function(e) return tostring(e) end)
    print("== " .. name .. "  ran=" .. tostring(ok) .. " err=" .. tostring(err):sub(1, 60))
    for _, c in ipairs(calls) do print("   CALL", c) end
    for i = math.max(1, #notes - 8), #notes do print("   NOTE", notes[i]) end
end

runVariant("b_string",  '{"a":1,"b":"abcdef0123456789abcdef0123456789","c":"x"}')
runVariant("b_empty_s", '{"a":1,"b":"","c":""}')
runVariant("a_string",  '{"a":"abcdef0123456789abcdef0123456789","b":1,"c":"x"}')
