local luau = require("@lune/luau")
local fs = require("@lune/fs")
local src = fs.readFile("C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_polsec1.lua")
local real = getfenv(0)
local missing = {}
local env: any = setmetatable({}, {
    __index = function(_, k)
        local v = real[k]
        if v == nil then missing[#missing + 1] = tostring(k) end
        return v
    end,
})
env.script_key = "trial"
env.game = setmetatable({}, {
    __index = function(_, k)
        if k == "HttpGet" then return function(_s, u) return '{"a":1,"b":1,"c":"x"}' end end
        if k == "GetService" then
            return function(_s, name)
                if name == "HttpService" then
                    return { JSONDecode = function(_s2, t) return { a = 1, b = 1, c = "x" } end }
                end
                return {}
            end
        end
        return nil
    end,
})
local okL, fn = pcall(luau.load, src, { environment = env, injectGlobals = false, debugName = "entry" })
print("compiled:", okL)
if not okL then return end
local ok, err = xpcall(fn, function(e) return tostring(e) end)
print("ran:", ok, tostring(err):sub(1, 120))
print("missing globals:", table.concat(missing, ", "))
