local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local path = process.env.POLFILE or "C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_polsec_a.lua"
local src = fs.readFile(path)
local real = getfenv(0)

local BIGGEST: { string } = {}
local realConcat = table.concat
local realChar = string.char
local function track(s: string)
	if #s < 1000 then return end
	BIGGEST[#BIGGEST + 1] = s
	table.sort(BIGGEST, function(a, b) return #a > #b end)
	if #BIGGEST > 8 then table.remove(BIGGEST) end
end

local function bh(name: string): any
	return setmetatable({}, {
		__index = function(_, k) return bh(name .. "." .. tostring(k)) end,
		__call = function() return bh(name .. "[c]") end,
		__tostring = function() return name end,
		__len = function() return 0 end, __add = function() return 0 end,
		__sub = function() return 0 end, __eq = function() return false end,
		__lt = function() return false end, __le = function() return false end,
		__concat = function() return "" end, __metatable = "locked",
	})
end

local env: any = setmetatable({}, {
	__index = function(_, k)
		local rv = (real :: any)[k]
		if rv ~= nil then return rv end
		return bh(tostring(k))
	end,
})
env.script_key = process.env.POLKEY or "trial"

local function concatSpy(tbl: any, sep: any?)
	local ok, res = pcall(realConcat, tbl, sep)
	if ok and type(res) == "string" then track(res) end
	if ok then return res else return realConcat(tbl) end
end
local function charSpy(...)
	local ok, res = pcall(realChar, ...)
	if ok and type(res) == "string" then track(res) end
	if ok then return res else return realChar(...) end
end
env.string = setmetatable({}, { __index = function(_, k: any)
	if k == "char" then return charSpy end
	return (real :: any).string[k]
end })
env.table = setmetatable({}, { __index = function(_, k: any)
	if k == "concat" then return concatSpy end
	return (real :: any).table[k]
end })

local waits = 0
local function waitish() waits += 1; if waits > 3 then error("WAIT_SPIN", 0) end end
env.task = bh("task"); env.task.wait = waitish
env.wait = waitish
env.getgenv = function() return env end
env.getfenv = function() return env end
env.setfenv = function(_, e) return env end
env.loadstring = function() return function() return nil end end
env.load = env.loadstring

local httpService: any = {}
httpService.JSONDecode = function(_, s)
	return setmetatable({}, { __index = function() return nil end })
end
httpService.JSONEncode = function() return "{}" end
local gameObj: any = bh("game")
gameObj.HttpService = httpService
local function http()
	return function() return { StatusCode = 200, Success = true, Headers = {}, Body = "{}" } end
end
gameObj.HttpGet = http()
gameObj.GetService = function(_, n)
	if tostring(n) == "HttpService" then return httpService end
	return bh("svc:" .. tostring(n))
end
env.game = gameObj
env.workspace = bh("workspace")
env.Enum = bh("Enum")
env.Instance = setmetatable({}, { __index = function() return function() return bh("inst") end end })
env.cloneref = function(v) return v end
env.request = http()

local okLoad, fn = pcall(luau.load, src, { environment = env, injectGlobals = false })
if not okLoad then print("LOAD FAILED", tostring(fn):sub(1, 200)); return end
xpcall(fn, function(e) return tostring(e) end)

if #BIGGEST == 0 then print("no big artifacts captured"); return end
for i, s in ipairs(BIGGEST) do
	print(string.format("artifact[%d] len=%d", i, #s))
end
local prog = BIGGEST[1]
local outPath = process.env.POLOUT or "C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_pol_program.bin"
fs.writeFile(outPath, prog)
print(string.format("wrote %d bytes to %s", #prog, outPath))

local counts: { [number]: number } = {}
for i = 1, #prog do
	local b = string.byte(prog, i)
	counts[b] = (counts[b] or 0) + 1
end
local distinct = 0
for _ in pairs(counts) do distinct += 1 end
print(string.format("distinct byte values: %d/256", distinct))
local head: { string } = {}
for i = 1, math.min(64, #prog) do head[i] = string.format("%02x", string.byte(prog, i)) end
print("head hex: " .. table.concat(head, " "))
