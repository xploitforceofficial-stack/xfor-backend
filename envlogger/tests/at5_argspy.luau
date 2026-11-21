local fs = require("@lune/fs")
local Sandbox = require("../src/core/sandbox")

local result = Sandbox.run([[
	local s = { x = workspace }
	print("typeof_s:", type(s), typeof(s))
	local k2, v2 = next(s, nil)
	print("spyval:", k2, v2, type(v2))
	print("rawnext:", rawget and "has rawget" or "no")
]], { timeout = 30, maxExplored = 0 })

print("ok:", result.ok, "err:", tostring(result.err):sub(1, 300))
for _, entry in ipairs(result.outputs or {}) do
	print("out:", entry.text)
end
