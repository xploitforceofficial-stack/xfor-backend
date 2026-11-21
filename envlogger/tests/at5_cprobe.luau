local fs = require("@lune/fs")
local Sandbox = require("../src/core/sandbox")

local result = Sandbox.run([[
	local names = { "getmetatable", "setmetatable", "tonumber", "tostring", "rawset", "rawget", "select", "xpcall", "assert", "error", "pcall", "type", "next", "getfenv", "setfenv", "typeof", "gmatch", "format" }
	local fns = { getmetatable, setmetatable, tonumber, tostring, rawset, rawget, select, xpcall, assert, error, pcall, type, next, getfenv, setfenv, typeof, string.gmatch, string.format }
	for i = 1, #names do
		local fn = fns[i]
		local source, line, fnName, parameters, variadic = debug.info(fn, "slnaf")
		print(string.format("%-14s src=%-8s line=%-4s name=%-12s params=%s vararg=%s",
			names[i], tostring(source), tostring(line), tostring(fnName), tostring(parameters), tostring(variadic)))
	end
]], { timeout = 30, maxExplored = 0 })

print("ok:", result.ok, "err:", tostring(result.err):sub(1, 200))
for _, e in ipairs(result.outputs or {}) do print("out:", e.text) end
