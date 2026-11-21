local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local path = process.env.POLFILE or "C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_polsec_a.lua"
local src = fs.readFile(path)
local real = getfenv(0)

local captured: { string } = {}
local loads = 0

local function blackhole(): any
    local t: any
    t = setmetatable({}, {
        __index = function() return blackhole() end,
        __call = function() return blackhole() end,
        __tostring = function() return "blackhole" end,
        __len = function() return 0 end,
        __add = function() return 0 end,
        __concat = function() return "" end,
    })
    return t
end

local env: any = setmetatable({}, {
    __index = function(_, k)
        local realValue = real[k]
        if realValue ~= nil then
            return realValue
        end
        return blackhole()
    end,
})

env.script_key = process.env.POLKEY or "trial"

local function hookedLoad(s: any, name: any)
    loads += 1
    if type(s) == "string" then
        captured[#captured + 1] = s
        print(string.format("captured chunk #%d len=%d name=%s", loads, #s, tostring(name)))
    else
        print(string.format("load called with %s", type(s)))
    end
    return function() return nil end
end
env.loadstring = hookedLoad
env.load = hookedLoad

local t0 = os.clock()
local okLoad, fn = pcall(luau.load, src, { environment = env, injectGlobals = false })
if not okLoad then
    print("LOAD FAILED", tostring(fn):sub(1, 300))
    return
end
local ok, err = xpcall(fn, function(e)
    return tostring(e) .. "\n" .. tostring(debug.traceback("", 2))
end)
print(string.format("native ok=%s wall=%.1fs loads=%d", tostring(ok), os.clock() - t0, loads))
if not ok then print("ERR:", tostring(err):sub(1, 900)) end
for i, s in ipairs(captured) do
    print(string.format("--- captured[%d] len=%d", i, #s))
    print(s:sub(1, 400))
end
