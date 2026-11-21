local fs = require("@lune/fs")
local luau = require("@lune/luau")
local src = fs.readFile("C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_polsec_a.lua")
local realGlobals = getfenv(0)
local captured: { string } = {}
local calls = 0
local env = setmetatable({}, { __index = realGlobals })
env.script_key = "trial"
local function hookLoad(s: any, _name: any)
    calls += 1
    if type(s) == "string" and #captured < 8 then captured[#captured + 1] = s end
    return function() return nil end
end
env.loadstring = hookLoad
env.load = hookLoad

local function stubTable(): any
    return setmetatable({}, { __index = function(_, k) return function() return nil end end, __call = function() return nil end })
end
env.game = stubTable()
env.workspace = stubTable()
env.Instance = setmetatable({ new = stubTable }, { __index = function() return stubTable end })
env.HttpService = stubTable()
env.game.GetService = function() return stubTable() end
local t0 = os.clock()
local okLoad, fn = pcall(luau.load, src, { environment = env, injectGlobals = false })
if not okLoad then print("LOAD FAILED", tostring(fn):sub(1, 200)) return end
local ok, err = pcall(fn)
print(string.format("native-decode ok=%s err=%s wall=%.1fs loadCalls=%d", tostring(ok), tostring(err):sub(1, 180), os.clock() - t0, calls))
for i, s in ipairs(captured) do
    print(string.format("  captured[%d] len=%d head=%q", i, #s, s:sub(1, 80)))
end
