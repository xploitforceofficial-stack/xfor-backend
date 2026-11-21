local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local path = process.env.POLFILE or "C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_polsec_a.lua"
local src = fs.readFile(path)
local real = getfenv(0)
local MODE = process.env.POLMODE or "truthy"
local LOG = {}

local function log(s: string)
    if #LOG < 400 then LOG[#LOG + 1] = s end
end

local function repr(v: any): string
    if type(v) == "string" then
        return string.format("%q", #v > 60 and (v:sub(1, 50) .. "...(" .. #v .. "b)") or v)
    end
    return tostring(v)
end

local function bh(name: string): any
    return setmetatable({}, {
        __index = function(_, k) return bh(name .. "." .. tostring(k)) end,
        __call = function(_, ...) return bh(name .. "[call]") end,
        __tostring = function() return name end,
        __len = function() return 0 end,
        __concat = function() return "" end,
        __eq = function() return false end,
    })
end

local waits = 0
local function spin(t: any)
    waits += 1
    if waits > 5 then error("HUNG", 0) end
    return t
end

local function anyTable(name: string, fill: any): any
    return setmetatable({}, {
        __index = function(_, k)
            log("FIELD[" .. name .. "]." .. tostring(k))
            return fill
        end,
        __len = function() return 0 end,
        __eq = function(_, other)
            log("EQ[" .. name .. "] vs " .. repr(other))
            return true
        end,
    })
end

local DIGEST_FILE = process.env.POLDIGEST or "C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_pol_digest.bin"

local function makeResult(): any
    if MODE == "feed" or MODE == "custom" then
        local file = process.env.POLC or DIGEST_FILE
        local ok, sig = pcall(fs.readFile, file)
        if not ok then
            log("FEED failed: " .. tostring(sig))
            return {}
        end
        if type(sig) == "buffer" then sig = buffer.tostring(sig) end
        local a = tonumber(process.env.POLA or "0")
        local b = tonumber(process.env.POLB or "0")
        log(string.format("FEED %s len=%d a=%d b=%d", file, #sig, a, b))
        return { a = a, b = b, c = sig }
    end
    if MODE == "feedhex" then
        local ok, hex = pcall(fs.readFile, DIGEST_FILE)
        if not ok then return {} end
        local out = {}
        for i = 1, #hex, 2 do
            out[#out + 1] = string.char(tonumber(hex:sub(i, i + 1), 16))
        end
        log(string.format("FEEDHEX digest len=%d", #out))
        return { a = 0, b = 0, c = table.concat(out) }
    end
    if MODE == "spyc" then
        local inner = setmetatable({}, {
            __index = function(_, k)
                log("C[" .. tostring(k) .. "]")
                return function(...) log("C[" .. tostring(k) .. "]() called"); return nil end
            end,
            __call = function(...) log("C() called"); return nil end,
            __len = function() log("#C"); return 0 end,
            __concat = function(_, other) log("C .. " .. repr(other)); return "" end,
            __eq = function(_, other) log("C == " .. repr(other)); return true end,
            __tostring = function() return "<C>" end,
        })
        return { a = 0, b = 0, c = inner }
    end
    if MODE == "empty" then return {} end
    if MODE == "truthy" then return anyTable("json", true) end
    if MODE == "one" then return anyTable("json", 1) end
    if MODE == "zero" then return anyTable("json", 0) end
    if MODE == "emptystr" then return anyTable("json", "") end
    if MODE == "rawstr" then return process.env.POLGATE or "{}" end
    return {}
end

local gateSeen = false
local env: any = setmetatable({}, {
    __index = function(_, k)
        local rv = real[k]
        if gateSeen then log("READ " .. tostring(k) .. " (" .. type(rv) .. ")") end
        if rv ~= nil then return rv end
        if not gateSeen then log("GLOBAL " .. tostring(k)) end
        return bh(tostring(k))
    end,
})

local recent = {}
local function note(v: any)
    if type(v) == "string" and #v >= 4 and #v <= 200 then
        recent[#recent + 1] = v
        if #recent > 40 then table.remove(recent, 1) end
    end
end

local realTable = real.table
local realString = real.string
local tableProxy = setmetatable({}, {
    __index = function(_, k)
        if k == "concat" then
            return function(t, sep)
                local out = realTable.concat(t, sep)
                note(out)
                return out
            end
        end
        return realTable[k]
    end,
})
local stringProxy = setmetatable({}, {
    __index = function(_, k)
        if k == "format" then
            return function(f, ...)
                local out = realString.format(f, ...)
                note(out)
                return out
            end
        end
        if k == "char" then
            return function(...)
                local out = realString.char(...)
                if #out >= 12 then note(out) end
                return out
            end
        end
        return realString[k]
    end,
})

env.script_key = process.env.POLKEY or "trial"
env.table = tableProxy
env.string = stringProxy
env.warn = function(...) log("WARN " .. table.concat({ ... }, " ")) end
env.print = function(...) log("PRINT " .. table.concat({ ... }, " ")) end
env.task = bh("task")
env.task.wait = spin
env.wait = spin
env.tick = function() return os.clock() end
env.time = function() return os.time() end
env.getgenv = function() return env end
env.getfenv = function() return env end
env.setfenv = function(_, _e) return env end
env.loadstring = function(s: any)
    log("LOADSTRING " .. (type(s) == "string" and ("len=" .. #s) or type(s)))
    return function() return nil end
end
env.load = env.loadstring

local GATEBODY = process.env.POLGATE or '{"a":0,"b":0,"c":"No fingerprint found"}'

local loggedGate = false
local function gateBody(url: string): any
    if string.find(url, "getpolsec", 1, true) then
        if not loggedGate then
            loggedGate = true
            log("GATE " .. url:sub(1, 130))
            gateSeen = true
        end
        return GATEBODY
    end
    return bh("http")
end

local function resp(url: string): any
    return {
        StatusCode = 200, StatusMessage = "OK", Success = true,
        Body = gateBody(url), Headers = {},
    }
end

env.request = function(a: any)
    local url = (type(a) == "table") and (a.Url or a.url) or a
    return resp(tostring(url))
end
env.http_request = env.request
env.syn_request = env.request
env.HttpGet = function(u: any) return gateBody(tostring(u)) end

local hs: any = {}
hs.JSONDecode = function(...)
    log("JSONDecode called -> mode=" .. MODE)
    return makeResult()
end
hs.JSONEncode = function() return "{}" end

local gameObj: any = {}
gameObj.HttpService = hs
gameObj.GetService = function(_, n: any)
    log("GetService " .. tostring(n))
    if tostring(n) == "HttpService" then return hs end
    return bh("svc:" .. tostring(n))
end
gameObj.HttpGet = function(_, u: any) return gateBody(tostring(u)) end
gameObj.PlaceId = 0
env.game = gameObj
env.workspace = bh("workspace")
env.Enum = bh("Enum")
env.Instance = setmetatable({}, { __index = function() return function() return bh("inst") end end })
env.instances = bh("instances")
env.syn = bh("syn")
env.cloneref = function(v) return v end
env.identifyexecutor = function() return "Roblox" end

local okLoad, fn = pcall(luau.load, src, { environment = env, injectGlobals = false })
if not okLoad then
    print("LOAD FAILED " .. tostring(fn):sub(1, 300))
    return
end
local ok, err = xpcall(fn, function(e) return tostring(e) end)
print(string.format("mode=%s ok=%s err=%s waits=%d", MODE, tostring(ok), tostring(err):sub(1, 80), waits))
for _, l in ipairs(LOG) do print(l) end
print("=== last strings before the kill (" .. #recent .. ") ===")
for _, s in ipairs(recent) do
    print(string.format("STR len=%d %q", #s, #s > 120 and (s:sub(1, 110) .. "...") or s))
end

if MODE == "capture" then
    local seen = {}
    local n = 0
    for _, s in ipairs(recent) do
        if #s == 32 and not seen[s] then
            seen[s] = true
            n += 1
            local f = string.format("C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_pol_sig%d.bin", n)
            fs.writeFile(f, s)
            local hex = {}
            for i = 1, 32 do hex[i] = string.format("%02x", string.byte(s, i)) end
            print(string.format("CAPTURED sig%d = %s", n, table.concat(hex)))
        end
    end
    if n == 0 then print("NO 32-byte digest captured") end
end
