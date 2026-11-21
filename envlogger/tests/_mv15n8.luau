local luau = require("@lune/luau")
local fs = require("@lune/fs")
local src = fs.readFile("C:/Users/Sandr/OneDrive/Desktop/OmniDBF/Samples/Moonveli/v2.0.15/1.lua")
local real = getfenv(0)
local notes: { string } = {}
local function note(s) notes[#notes + 1] = tostring(s):sub(1, 130) end

local function dbgWrap(name: string, f: any): any
    return function(...)
        local args: { string } = {}
        for i = 1, select("#", ...) do
            local v = select(i, ...)
            args[#args + 1] = type(v) == "function" and "fn" or tostring(v):sub(1, 40)
        end
        local r: any = table.pack(pcall(f, ...))
        local ok = r[1]
        local res: { string } = {}
        for i = 2, r.n do
            local v = r[i]
            res[#res + 1] = type(v) == "function" and "fn" or (v == nil and "nil" or tostring(v):sub(1, 40))
        end
        note("debug." .. name .. "(" .. table.concat(args, ",") .. ") -> " .. (ok and table.concat(res, ",") or "ERR " .. tostring(r[2]):sub(1, 60)))
        if not ok then error(r[2], 0) end
        return table.unpack(r, 2, r.n)
    end
end
local debugT: any = {}
for k, v in pairs(real.debug) do
    if type(v) == "function" then debugT[k] = dbgWrap(k, v) else debugT[k] = v end
end

local enumRoot: any = setmetatable({}, { __index = function(_e, k)
    note("Enum." .. tostring(k))
    if k == "Material" or k == "Font" then
        return setmetatable({}, { __index = function(_t2, ik)
            note("Enum." .. tostring(k) .. "." .. tostring(ik))
            return nil
        end })
    end
    error(string.format('%s is not a valid member of "Enum"', tostring(k)), 2)
end })

local gameObj: any = setmetatable({}, { __index = function(_g, gk)
    if gk == "GetService" then
        return function(_s, n)
            note("GetService " .. tostring(n))
            return setmetatable({}, {})
        end
    end
    error(tostring(gk) .. " is not a valid member of DataModel", 2)
end })

local env: any = setmetatable({}, { __index = function(_, k)
    note("G?" .. tostring(k))
    local v = real[k]
    if v ~= nil then return v end
    if k == "game" then return gameObj end
    if k == "Enum" then return enumRoot end
    if k == "debug" then return debugT end
    return nil
end })
env.print = function(...) local p = {}; for i = 1, select("#", ...) do p[i] = tostring(select(i, ...)) end note("PRINT " .. table.concat(p, " ")) end
env.warn = function(...) local p = {}; for i = 1, select("#", ...) do p[i] = tostring(select(i, ...)) end note("WARN " .. table.concat(p, " ")) end

local okL, fn = pcall(luau.load, src, { environment = env, injectGlobals = false, debugName = "e" })
if not okL then print("COMPILE-FAIL", tostring(fn):sub(1, 200)); return end
local t0 = os.clock()
local ok, err = xpcall(fn, function(e) return tostring(e) end)
print(("ran ok=%s %.2fs notes=%d"):format(tostring(ok), os.clock() - t0, #notes))
print("err:", tostring(err):sub(1, 200))
local fsL = require("@lune/fs")
local f = fsL.writeFile("mv15_notes.txt", table.concat(notes, string.char(10)))
print("--- notes tail:")
for i = math.max(1, #notes - 20), #notes do print("  ", notes[i]) end
