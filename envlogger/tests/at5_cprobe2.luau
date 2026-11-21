local fs = require("@lune/fs")
local Sandbox = require("../src/core/sandbox")

local result = Sandbox.run([[
	local fn = getmetatable
	local a, b, c, d, e, f = debug.info(fn, "slnaf")
	print("getmetatable slnaf:", a, b, c, d, e, f)
	local g, h = debug.info(fn, "sn")
	print("sn:", g, h)
]], { timeout = 30, maxExplored = 0 })

print("ok:", result.ok, "err:", tostring(result.err):sub(1, 200))
for _, e in ipairs(result.outputs or {}) do print("out:", e.text) end
