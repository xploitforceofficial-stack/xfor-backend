local luau = require("@lune/luau")
local fs = require("@lune/fs")
local src = fs.readFile("C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_polsec1.lua")

local pre = "local __FUHD_CHECK__ = __FUHD_CHECK__;"
local chunk = pre .. src

local real = getfenv(0)
local env: any = setmetatable({}, { __index = function(_, k) return real[k] end })
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
local okL, fn = pcall(luau.load, chunk, { environment = env, injectGlobals = false, debugName = "entry" })
print("compiled:", okL, fn)
if not okL then return end
local ok, err = xpcall(fn, function(e) return tostring(e) .. " TB " .. debug.traceback(tostring(e), 2) end)
print("ran:", ok)
print(err)
