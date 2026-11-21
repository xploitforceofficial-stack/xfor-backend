local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local path = process.env.POLFILE or "C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_polsec_a.lua"
local src = fs.readFile(path)
local real = getfenv(0)

local function repr(v: any): string
	if typeof(v) == "string" then
		return string.format("%q", #v > 60 and (v:sub(1, 50) .. "…") or v)
	elseif typeof(v) == "table" then
		local parts = {}
		for i, x in ipairs(v) do parts[i] = repr(x); if i > 4 then parts[i] = "…" break end end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	return tostring(v)
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

local function jsonToValue(s: string): any

	local out: { [string]: any } = {}
	for k, v in s:gmatch('"([%w_]+)"%s*:%s*("([^"]*)"|[-%d%.eE]+|true|false|null)') do
		if v:sub(1, 1) == '"' then
			out[k] = v:sub(2, -2)
		elseif v == "true" then
			out[k] = true
		elseif v == "false" then
			out[k] = false
		elseif v == "null" then
			out[k] = nil
		else
			out[k] = tonumber(v)
		end
	end
	return out
end

local function runOnce(body: string): (string, number, number, { string })
	local LOG: { string } = {}
	local captured: { string } = {}
	local waits = 0
	local function log(s: string) if #LOG < 60 then LOG[#LOG + 1] = s end end

	local env: any = setmetatable({}, {
		__index = function(_, k)
			local rv = (real :: any)[k]
			if rv ~= nil then return rv end
			log("G:" .. tostring(k))
			return bh(tostring(k))
		end,
	})
	env.script_key = process.env.POLKEY or "trial"

	local parsed: any = jsonToValue(body)
	local reads: { string } = {}
	local httpService: any = {}
	httpService.JSONDecode = function(_, s: any)
		log("JSONDecode " .. repr(s))
		return setmetatable({}, { __index = function(_, k)
			local key = tostring(k)
			reads[#reads + 1] = key
			return parsed[key]
		end })
	end
	httpService.JSONEncode = function(_, v) return "{}" end

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
	env.getgenv = function() return env end
	env.getfenv = function() return env end
	env.setfenv = function(_, e) return env end
	env.loadstring = function(s: any)
		if type(s) == "string" then captured[#captured + 1] = s end
		return function() return nil end
	end
	env.load = env.loadstring
	env.tick = os.clock
	env.time = os.time

	local gameObj: any = bh("game")
	gameObj.HttpService = httpService
	local function http()
		return function(...)
			local a = { ... }
			local first = a[1]
			local url = if typeof(first) == "table" then tostring(first.Url or first.url or "") else tostring(first)
			log("HTTP " .. url:sub(1, 130))
			return { StatusCode = 200, StatusMessage = "OK", Success = true, Headers = {}, Body = body, body = body }
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
	if not okLoad then return "loadfail " .. tostring(fn):sub(1, 80), waits, #captured, reads end
	local ok, err = xpcall(fn, function(e) return tostring(e) end)
	local errLine = if ok then "OK" else tostring(err):gsub("WAIT_SPIN", "SPIN")
	return errLine, waits, #captured, reads
end

local variants: { { string } } = {
	{ "real-server", '{"a":0,"b":0,"c":"No fingerprint found"}' },
}

local bigPath = process.env.POLCBIG
if bigPath then
	local big = fs.readFile(bigPath)
	print(string.format("big variant: %d bytes from %s", #big, bigPath))

	local esc = big:gsub('\\', "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r")
	table.insert(variants, { "big-c", '{"a":1,"b":1,"c":"' .. esc .. '"}' })
end
local extraC = process.env.POLCC
if extraC then
	table.insert(variants, { "custom-c", extraC })
end
for _, v in ipairs(variants) do
	local t0 = os.clock()
	local errLine, waits, ncap, reads = runOnce(v[2])
	print(string.format("%-12s (%.1fs) -> err=%s waits=%d captured=%d reads=[%s]",
		v[1], os.clock() - t0, tostring(errLine):sub(1, 60), waits, ncap, table.concat(reads, ",")))
	if ncap > 0 then print("    CAPTURED PAYLOAD!") end
end
