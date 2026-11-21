local luau = require("@lune/luau")
local fs = require("@lune/fs")
local src = fs.readFile("C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_polsec1.lua")
local real = getfenv(0)
local calls = {}
local env: any = setmetatable({}, {
    __index = function(_, k)
        local v = real[k]
        return v
    end,
})
env.script_key = "trial"
env.request = function(a)
    local url = type(a) == "table" and (a.Url or a.url) or a
    calls[#calls + 1] = "request " .. tostring(url):sub(1, 120)
    return { StatusCode = 200, Success = true, Body = '{"a":1,"b":1,"c":"x"}', Headers = {} }
end
env.game = setmetatable({}, {
    __index = function(_, k)
        if k == "HttpGet" then return function(_s, u) calls[#calls+1] = "HttpGet " .. tostring(u):sub(1,120); return '{"a":1,"b":1,"c":"x"}' end end
        if k == "GetService" then
            return function(_s, name)
                if name == "HttpService" then
                    return { JSONDecode = function(_s2, t) calls[#calls+1] = "JSONDecode " .. tostring(t):sub(1,80); return { a = 1, b = 1, c = "x" } end }
                end
                return {}
            end
        end
        return nil
    end,
})
env.wait = function(t) error("WAIT " .. tostring(t), 0) end
env.task = setmetatable({}, { __index = function() return function() error("TASKWAIT", 0) end end })
local okL, fn = pcall(luau.load, src, { environment = env, injectGlobals = false, debugName = "entry" })
print("compiled:", okL)
if not okL then return end
local ok, err = xpcall(fn, function(e) return tostring(e) end)
print("ran:", ok, tostring(err):sub(1, 160))
for _, c in ipairs(calls) do print("CALL", c) end
