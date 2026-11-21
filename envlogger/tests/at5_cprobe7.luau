local fs = require("@lune/fs")
local Sandbox = require("../src/core/sandbox")

local result = Sandbox.run([[
	local function probe(label, fn)
		local ok, a, b, c, d, e = pcall(debug.info, fn, "slnaf")
		if ok then
			print(label, a, b, c, d, e)
		else
			print(label, "ERR", a)
		end
	end
	probe("getmetatable", getmetatable)
	probe("string.byte", string.byte)
	probe("tostring", tostring)
	probe("pcall", pcall)
]], { timeout = 30, maxExplored = 0 })

print("ok:", result.ok, "err:", tostring(result.err):sub(1, 200))
for _, e in ipairs(result.outputs or {}) do print("out:", e.text) end
