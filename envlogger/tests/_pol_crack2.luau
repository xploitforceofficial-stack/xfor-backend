local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local path = process.env.POLFILE or "C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_polsec_a.lua"
local src = fs.readFile(path)
local real = getfenv(0)

local FIXED_TIME = 1790000000
local FIXED_CLOCK = 1234.5

local function repr(v: any): string
	if typeof(v) == "string" then
		return string.format("%q", #v > 60 and (v:sub(1, 50) .. "…(" .. #v .. "b)") or v)
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
		__sub = function() return 0 end, __mul = function() return 0 end,
		__div = function() return 0 end, __eq = function() return false end,
		__lt = function() return false end, __le = function() return false end,
		__concat = function() return "" end, __metatable = "locked",
	})
end

local function runOnce(cValue: any): any
	local LOG: { string } = {}
	local captured: { string } = {}
	local TAIL: { string } = {}
	local waits = 0
	local t0 = os.clock()

	local function log(s: string) if #LOG < 80 then LOG[#LOG + 1] = s end end

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
	local function track(s: string)
		if #s == 32 then
			TAIL[#TAIL + 1] = s
			if #TAIL > 40 then table.remove(TAIL, 1) end
		end
	end
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
		local r = (real :: any).os[k]
		if k == "time" then return function() return FIXED_TIME end end
		if k == "clock" then return function() return FIXED_CLOCK end end
		return r
	end })
	env.math = setmetatable({}, { __index = function(_, k: any)
		local r = (real :: any).math[k]
		if k == "random" then return function(a: any, b: any)
			if a == nil then return 0.5 end
			if b == nil then return math.floor(a / 2) end
			return math.floor((a + b) / 2)
		end end
		if k == "randomseed" then return function() end end
		return r
	end })
	env.getgenv = function() return env end
	env.getfenv = function() return env end
	env.setfenv = function(_, e) return env end
	env.loadstring = function(s: any, nm: any)
		if type(s) == "string" then captured[#captured + 1] = s end
		return function() return nil end
	end
	env.load = env.loadstring
	env.tick = function() return FIXED_CLOCK end
	env.time = function() return FIXED_TIME end

	local jsonReads: { string } = {}
	local httpService: any = {}
	httpService.JSONDecode = function(_, s: any)
		log("JSONDecode " .. repr(s))
		return setmetatable({}, { __index = function(_, k)
			local key = tostring(k)
			jsonReads[#jsonReads + 1] = key
			if key == "c" then return cValue end
			local defaults: { [string]: any } = {
				success = true, valid = true, ok = true, whitelisted = true,
				expired = false, banned = false,
				expiry = FIXED_TIME + 86400 * 365, expires = FIXED_TIME + 86400 * 365,
				a = 1, b = FIXED_TIME + 86400 * 365, message = "ok",
			}
			return defaults[key]
		end })
	end
	httpService.JSONEncode = function() return "{}" end

	local gameObj: any = bh("game")
	gameObj.HttpService = httpService
	local function http()
		return function(...)
			local a = { ... }
			local first = a[1]
			local url = if typeof(first) == "table" then tostring(first.Url or first.url or "") else tostring(first)
			log("HTTP " .. url:sub(1, 140))
			return { StatusCode = 200, StatusMessage = "OK", Success = true, Headers = {},
				Body = '{"a":1,"b":1}', body = '{"a":1,"b":1}' }
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
	if not okLoad then
		return { err = "loadfail " .. tostring(fn):sub(1, 100), captured = captured, log = LOG, digests = {}, waits = waits, wall = os.clock() - t0 }
	end
	local ok, err = xpcall(fn, function(e) return tostring(e) end)
	return {
		err = if ok then nil else tostring(err),
		captured = captured, log = LOG, digests = TAIL,
		jsonReads = jsonReads, waits = waits, wall = os.clock() - t0,
	}
end

local function hexOf(s: string): string
	local hex = {}
	for i = 1, #s do hex[i] = string.format("%02x", string.byte(s, i)) end
	return table.concat(hex)
end

local r = runOnce("x")
print(string.format("r0: err=%s wall=%.2fs captured=%d jsonReads=%s", tostring(r.err), r.wall, #r.captured, table.concat(r.jsonReads or {}, ",")))
for _, l in ipairs(r.log) do print("   " .. l:sub(1, 170)) end
local seen: { [string]: boolean } = {}
local cands: { string } = {}
for _, d in ipairs(r.digests) do
	if not seen[d] then seen[d] = true; cands[#cands + 1] = d end
end
print(string.format("r0: %d distinct 32-byte digests", #cands))
for i, d in ipairs(cands) do print(string.format("   digest[%d] %s", i, hexOf(d))) end

local best = cands
for round = 1, 6 do
	local roundCaptured = 0
	local nextCands: { string } = {}
	local nextSeen: { [string]: boolean } = {}
	for i, c in ipairs(best) do
		local rr = runOnce(c)
		local hex = hexOf(c)
		print(string.format("r%d[%d] c=%s…: err=%s captured=%d newDigests=%d",
			round, i, hex:sub(1, 12), tostring(rr.err):sub(1, 50), #rr.captured, #(rr.digests or {})))
		roundCaptured += #rr.captured
		if #rr.captured > 0 then
			for j, s in ipairs(rr.captured) do
				print(string.format("   PAYLOAD[%d] len=%d head=%s", j, #s, string.format("%q", s:sub(1, 160))))
			end
		end
		for _, l in ipairs(rr.log) do print("     " .. l:sub(1, 170)) end
		for _, d in ipairs(rr.digests or {}) do
			if not nextSeen[d] and not seen[d] then
				nextSeen[d] = true
				nextCands[#nextCands + 1] = d
			end
		end
	end
	if roundCaptured > 0 then print("STOP: payload captured"); break end
	if #nextCands == 0 then print("STOP: no new digests"); break end
	for _, d in ipairs(nextCands) do seen[d] = true end
	best = nextCands
end
print("done.")
