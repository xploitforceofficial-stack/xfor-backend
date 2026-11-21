local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local path = process.env.POLFILE or "C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_polsec_a.lua"
local src = fs.readFile(path)
local real = getfenv(0)
local FIXED_TIME = 1790000000
local FIXED_CLOCK = 1234.5

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

local function runOnce(cValue: any): (string, number, { string })
	local LOG: { string } = {}
	local captured: { string } = {}
	local waits = 0
	local function log(s: string) if #LOG < 40 then LOG[#LOG + 1] = s end end

	local env: any = setmetatable({}, {
		__index = function(_, k)
			local rv = (real :: any)[k]
			if rv ~= nil then return rv end
			log("G:" .. tostring(k))
			return bh(tostring(k))
		end,
	})
	env.script_key = process.env.POLKEY or "trial"

	local realConcat = table.concat
	local realChar = string.char
	env.string = setmetatable({}, { __index = function(_, k: any)
		return (real :: any).string[k]
	end })
	env.table = setmetatable({}, { __index = function(_, k: any)
		return (real :: any).table[k]
	end })

	local function repr(v: any): string
		if typeof(v) == "string" then return string.format("%q", #v > 50 and (v:sub(1, 40) .. "…") or v) end
		return tostring(v)
	end
	local function fmt(...)
		local parts = {}
		for i = 1, select("#", ...) do parts[i] = repr((select(i, ...))) end
		return table.concat(parts, " ")
	end
	env.warn = function(...) log("WARN " .. fmt(...)) end
	env.print = function(...) log("PRINT " .. fmt(...)) end
	local function waitish() waits += 1; if waits > 3 then error("WAIT_SPIN", 0) end end
	env.task = bh("task"); env.task.wait = waitish
	env.wait = waitish
	env.os = setmetatable({}, { __index = function(_, k: any)
		if k == "time" then return function() return FIXED_TIME end end
		if k == "clock" then return function() return FIXED_CLOCK end end
		return (real :: any).os[k]
	end })
	env.getgenv = function() return env end
	env.getfenv = function() return env end
	env.setfenv = function(_, e) return env end
	env.loadstring = function(s: any)
		if type(s) == "string" then captured[#captured + 1] = s end
		return function() return nil end
	end
	env.load = env.loadstring
	env.tick = function() return FIXED_CLOCK end
	env.time = function() return FIXED_TIME end

	local httpService: any = {}
	httpService.JSONDecode = function(_, s: any)
		log("JSONDecode " .. repr(s))
		return setmetatable({}, { __index = function(_, k)
			if tostring(k) == "c" then return cValue end
			local defaults: { [string]: any } = {
				success = true, valid = true, ok = true, whitelisted = true,
				expired = false, banned = false, a = 1, b = FIXED_TIME + 86400 * 365,
			}
			return defaults[tostring(k)]
		end })
	end
	httpService.JSONEncode = function() return "{}" end

	local gameObj: any = bh("game")
	gameObj.HttpService = httpService
	local CAPTURED_URLS: { string } = {}
	local function http()
		return function(...)
			local a = { ... }
			local first = a[1]
			local url = if typeof(first) == "table" then tostring(first.Url or first.url or "") else tostring(first)
			CAPTURED_URLS[#CAPTURED_URLS + 1] = url
			log("HTTP " .. url:sub(1, 140))
			return { StatusCode = 200, StatusMessage = "OK", Success = true, Headers = {}, Body = '{"a":1,"b":1}', body = '{"a":1,"b":1}' }
		end
	end
	gameObj.HttpGet = http()
	gameObj.GetService = function(_, n: any)
		if tostring(n) == "HttpService" then return httpService end
		log("SVC " .. tostring(n))
		return bh("svc:" .. tostring(n))
	end
	env.game = gameObj
	env.workspace = bh("workspace")
	env.Enum = bh("Enum")
	env.Instance = setmetatable({}, { __index = function() return function() return bh("inst") end end })
	env.cloneref = function(v) return v end
	env.identifyexecutor = function() return "Roblox" end
	env.request = http()
	env.http_request = http()
	env.HttpGet = http()

	local okLoad, fn = pcall(luau.load, src, { environment = env, injectGlobals = false })
	if not okLoad then return "loadfail", waits, captured end
	local ok, err = xpcall(fn, function(e) return tostring(e) end)
	local errLine = if ok then "OK" else tostring(err):gsub("WAIT_SPIN", "SPIN")
	return errLine, waits, captured
end

local CANDS: { string } = {
	"wl2_dfd48d7d0188647a71afd93b3aca1ede",
	"dfd48d7d0188647a71afd93b3aca1ede",
	"ed018291d0bbe89580083429f4230eb669ffd8574074af6e60a6c57f59654eb7",
	"trial",
	"39e08a56be5116710eea2aa5792ac5699abc0e3300404e31445e62f0f120dae9",
	"b8211aee3bf64c80c9c03d15a67d9d66d40b6cf0e0e19161a8f41b54383c8dcd",
	"\39\232\10\86\190\81\22\113\14\234\42\165\122\42\165\105\196\142\14\51\0\64\78\49\68\94\178\200\32\160",
	"true",
	"0",
	"1",
	"ok",
	"success",
	"whitelisted",
}
for i, c in ipairs(CANDS) do
	local errLine, waits, captured = runOnce(c)
	local label = c
	if #c > 24 then
		label = (c:gsub("[^%w%p]", "")):sub(1, 20) .. "…"
	end
	print(string.format("%2d c=%-24s err=%-40s captured=%d", i, label, tostring(errLine):sub(1, 40), #captured))
	if #captured > 0 then
		print("   *** PAYLOAD CAPTURED ***")
		for j, s in ipairs(captured) do
			print(string.format("   [%d] len=%d head=%s", j, #s, string.format("%q", s:sub(1, 200))))
		end
	end
end
