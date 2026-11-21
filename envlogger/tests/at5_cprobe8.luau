local fs = require("@lune/fs")
local Sandbox = require("../src/core/sandbox")

local result = Sandbox.run([[
	-- tostring is dual-wrapped (a table with __call); what do checks see?
	print("type(tostring):", type(tostring))
	print("typeof:", typeof(tostring))
	local ok, a, b, c, d, e = pcall(debug.info, tostring, "slnaf")
	print("info:", ok, a, b, c, d, e)
]], { timeout = 30, maxExplored = 0 })

print("ok:", result.ok, "err:", tostring(result.err):sub(1, 200))
for _, e in ipairs(result.outputs or {}) do print("out:", e.text) end
