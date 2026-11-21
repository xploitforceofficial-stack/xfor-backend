local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local path = process.env.POLFILE or "C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_polsec_a.lua"
local src = fs.readFile(path)
local real = getfenv(0)
local WAIT_LIMIT = 8

local function repr(v: any): string
	if typeof(v) == "string" then
		return string.format("%q", #v > 80 and (v:sub(1, 70) .. "…(" .. #v .. "b)") or v)
	elseif typeof(v) == "table" then
		local parts = {}
		for i, x in ipairs(v) do parts[i] = repr(x); if i > 6 then parts[i] = "…" break end end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	return tostring(v)
end

local function bh(name: string): any
	return setmetatable({}, {
		__index = function(_, k) return bh(name .. "." .. tostring(k)) end,
		__call = function() return bh(name .. "[c]") end,
		__tostring = function() return name end,
		__len = function() return 0 end,
		__add = function() return 0 end, __sub = function() return 0 end,
		__mul = function() return 0 end, __div = function() return 0 end,
		__eq = function() return false end, __lt = function() return false end,
		__le = function() return false end, __concat = function() return "" end,
		__metatable = "locked",
	})
end

local function runOnce(cValue: any): (any, { string }, { string })
	local LOG: { string } = {}
	local captured: { string } = {}
	local TAIL: { string } = {}
	local waits = 0

	local function log(s: string) if #LOG < 300 then LOG[#LOG + 1] = s end end

	local env: any = setmetatable({}, {
		__index = function(_, k)
			local rv = (real :: any)[k]
			if rv ~= nil then return rv end
			log("GLOBAL " .. tostring(k))
			return bh(tostring(k))
		end,
	})
	env.script_key = process.env.POLKEY or "trial"

	local realConcat = table.concat
	local realChar = string.char
	local function concatSpy(tbl: any, sep: any?)
		local ok, res = pcall(realConcat, tbl, sep)
		if ok and type(res) == "string" and #res >= 2 and #res <= 512 then
			TAIL[#TAIL + 1] = res
			if #TAIL > 200 then table.remove(TAIL, 1) end
		end
		if ok then return res else return realConcat(tbl) end
	end
	local function charSpy(...)
		local ok, res = pcall(realChar, ...)
		if ok and type(res) == "string" and #res >= 2 and #res <= 512 then
			TAIL[#TAIL + 1] = res
			if #TAIL > 200 then table.remove(TAIL, 1) end
		end
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
	env.warn = function(...) log("WARN: " .. fmt(...)) end
	env.print = function(...) log("PRINT: " .. fmt(...)) end
	local function waitish(t) waits += 1; if waits > WAIT_LIMIT then error("WAIT_SPIN", 0) end; return t end
	env.task = bh("task"); env.task.wait = waitish
	env.wait = waitish
	env.tick = os.clock
	env.time = os.time
	env.getgenv = function() return env end
	env.getfenv = function() return env end
	env.setfenv = function(_, e) return env end
	env.loadstring = function(s: any, nm: any)
		if type(s) == "string" then
			captured[#captured + 1] = s
			log(string.format("LOADSTRING len=%d name=%s", #s, tostring(nm)))
		else
			log("LOADSTRING nonstring " .. typeof(s))
		end
		return function() return nil end
	end
	env.load = env.loadstring

	local httpService: any = {}
	httpService.JSONDecode = function(_, s: any)
		log("JSONDecode " .. repr(s))
		return setmetatable({}, { __index = function(_, k)
			local key = tostring(k)
			if key == "c" then return cValue end
			log("json." .. key)
			local defaults: { [string]: any } = {
				success = true, valid = true, ok = true, whitelisted = true,
				expired = false, banned = false, expiry = os.time() + 86400 * 30,
				expires = os.time() + 86400 * 30, message = "ok", status = "ok",
			}
			if defaults[key] ~= nil then return defaults[key] end
			return bh("json." .. key)
		end })
	end
	httpService.JSONEncode = function(_, v) log("JSONEncode " .. repr(v)); return "{}" end

	local gameObj: any = bh("game")
	gameObj.HttpService = httpService
	local function http(which: string)
		return function(...)
			local a = { ... }
			local first = a[1]
			local url = if typeof(first) == "table" then tostring(first.Url or first.url or "") else tostring(first)
			log(string.format("%s url=%s", which, url:sub(1, 150)))
			return {
				StatusCode = 200, StatusMessage = "OK", Success = true, Headers = {},
				Body = '{"success":true,"valid":true,"whitelisted":true,"message":"ok"}',
				body = '{"success":true,"valid":true,"whitelisted":true,"message":"ok"}',
			}
		end
	end
	gameObj.HttpGet = http("game:HttpGet")
	gameObj.GetService = function(_, n: any)
		log("game:GetService " .. tostring(n))
		if tostring(n) == "HttpService" then return httpService end
		return bh("svc:" .. tostring(n))
	end
	env.game = gameObj
	env.workspace = bh("workspace")
	env.Enum = bh("Enum")
	env.Instance = setmetatable({}, { __index = function() return function() return bh("inst") end end })
	env.cloneref = function(v) return v end
	env.identifyexecutor = function() return "Roblox" end
	env.request = http("request")
	env.http_request = http("http_request")
	env.syn_request = http("syn_request")
	env.HttpGet = http("HttpGet")

	local okLoad, fn = pcall(luau.load, src, { environment = env, injectGlobals = false })
	if not okLoad then
		log("LOADFAILED " .. tostring(fn):sub(1, 200))
		return { captured = captured, log = LOG, tail = TAIL, err = "loadfail", waits = waits }
	end
	local ok, err = xpcall(fn, function(e) return tostring(e) end)
	return { captured = captured, log = LOG, tail = TAIL, err = if ok then nil else tostring(err), waits = waits }
end

local r1 = runOnce("x")
print(string.format("phase1: err=%s waits=%d captured=%d", tostring(r1.err), r1.waits, #r1.captured))
for _, l in ipairs(r1.log) do print("  " .. l:sub(1, 200)) end

local digests: { string } = {}
local seen: { [string]: boolean } = {}
for _, s in ipairs(r1.tail) do
	if #s == 32 and not seen[s] then
		seen[s] = true
		digests[#digests + 1] = s
	end
end
print(string.format("phase1: %d distinct 32-byte digests in tail", #digests))
for i, d in ipairs(digests) do
	local hex = {}
	for j = 1, #d do hex[j] = string.format("%02x", string.byte(d, j)) end
	print(string.format("  digest[%d] = %s", i, table.concat(hex)))
end

for i, d in ipairs(digests) do
	local r2 = runOnce(d)
	print(string.format("phase2 digest[%d]: err=%s waits=%d captured=%d", i, tostring(r2.err), r2.waits, #r2.captured))
	for _, l in ipairs(r2.log) do print("    " .. l:sub(1, 200)) end
	if #r2.captured > 0 then
		for j, s in ipairs(r2.captured) do
			print(string.format("    captured[%d] len=%d head=%s", j, #s, string.format("%q", s:sub(1, 200))))
		end
	end
end

for i, d in ipairs(digests) do
	local hex = {}
	for j = 1, #d do hex[j] = string.format("%02x", string.byte(d, j)) end
	local hexStr = table.concat(hex)
	local r3 = runOnce(hexStr)
	print(string.format("phase2b hex[%d]: err=%s waits=%d captured=%d", i, tostring(r3.err), r3.waits, #r3.captured))
	if #r3.captured > 0 then
		for _, l in ipairs(r3.log) do print("    " .. l:sub(1, 160)) end
		for j, s in ipairs(r3.captured) do
			print(string.format("    captured[%d] len=%d head=%s", j, #s, string.format("%q", s:sub(1, 200))))
		end
	end
end
