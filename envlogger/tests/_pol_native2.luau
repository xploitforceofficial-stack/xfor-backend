local fs = require("@lune/fs")
local luau = require("@lune/luau")
local src = fs.readFile("C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_polsec_a.lua")
local realGlobals = getfenv(0)
local reads: { string } = {}
local env = setmetatable({}, {
    __index = function(_, k)
        if type(k) == "string" and #reads < 60 then reads[#reads + 1] = k end
        return realGlobals[k]
    end,
})
env.script_key = "trial"
env.loadstring = function(s: any, n: any)
    print("LOADSTRING CALLED len=", type(s) == "string" and #s or type(s), tostring(n))
    return function() return nil end
end
local okLoad, fn = pcall(luau.load, src, { environment = env, injectGlobals = false })
if not okLoad then print("LOAD FAILED", tostring(fn):sub(1, 200)) return end
local ok, err = pcall(fn)
print("ok=", ok, "err=", tostring(err):sub(1, 200))
if not ok then print("TRACE:", debug.traceback("", 2):sub(1, 700)) end
print("first reads:", table.concat(reads, ", "))
