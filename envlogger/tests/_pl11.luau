local luau = require("@lune/luau")
local fs = require("@lune/fs")
local src = fs.readFile("C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_polsec1.lua")
local real = getfenv(0)

local reads: { string } = {}
local function track(t: any, label: string): any
	return setmetatable({}, {
		__index = function(_self, k)
			reads[#reads + 1] = label .. "." .. tostring(k)
			local v = real
			return nil
		end,
	})
end

local notes: { string } = {}
local function note(s) notes[#notes + 1] = tostring(s):sub(1, 140) end

local players: any = setmetatable({}, { __index = function(_, k)
	if k == "LocalPlayer" then
		return setmetatable({}, { __index = function(_t2, k2)
			if k2 == "Kick" then return function(_s, msg) note("KICK " .. tostring(msg):sub(1, 80)); error("KICKED", 0) end end
			note("LP." .. tostring(k2)); return nil
		end })
	end
	note("PL." .. tostring(k)); return nil
end })

local RESP: any
local function mkJson(body: string): any
	reads[#reads + 1] = "JSONDecode(" .. body:sub(1, 60) .. ")"
	return track({ a = 0, b = 0, c = "No fingerprint found" }, "json")
end

local env: any = setmetatable({}, { __index = function(_, k)
	local v = real[k]
	if v ~= nil then return v end
	note("G?" .. tostring(k))
	return nil
end })
env.script_key = "trial"
local respReads: { string } = {}
RESP = setmetatable({ StatusCode = 200, Success = true, Headers = {} }, {
	__index = function(_self, k)
		respReads[#respReads + 1] = "resp." .. tostring(k)
		if k == "Body" then return '{"a":0,"b":0,"c":"No fingerprint found"}' end
		return nil
	end,
})
env.game = setmetatable({}, { __index = function(_, k)
	if k == "HttpGet" then return function(_s, u) reads[#reads + 1] = "HttpGet"; return RESP end end
	if k == "GetService" then return function(_s, n)
		if n == "HttpService" then
			return { JSONDecode = function(_s2, t) return mkJson(t) end }
		end
		if n == "Players" then return players end
		note("svc " .. tostring(n))
		return setmetatable({}, {})
	end end
	note("game." .. tostring(k))
	return nil
end })
env.workspace = {}
env.request = function(_a) reads[#reads + 1] = "request"; return RESP end
env.wait = function(t) note("wait " .. tostring(t)); error("STOPWAIT", 0) end
env.task = setmetatable({}, { __index = function() return function() note("taskcall"); error("STOPTASK", 0) end end })
env.warn = function(...) local p = {}; for i = 1, select("#", ...) do p[i] = tostring(select(i, ...)) end note("WARN " .. table.concat(p, " ")) end
env.print = function(...) local p = {}; for i = 1, select("#", ...) do p[i] = tostring(select(i, ...)) end note("PRINT " .. table.concat(p, " ")) end

local okL, fn = pcall(luau.load, src, { environment = env, injectGlobals = false, debugName = "e" })
if not okL then print("COMPILE-FAIL"); return end
local ok, err = xpcall(fn, function(e) return tostring(e) end)
print("ran:", ok, tostring(err):sub(1, 60))
print("--- response-object reads:")
for _, r in ipairs(respReads) do print("  ", r) end
print("--- json + other reads:")
for _, r in ipairs(reads) do print("  ", r) end
print("--- notes tail:")
for i = math.max(1, #notes - 8), #notes do print("  ", notes[i]) end
