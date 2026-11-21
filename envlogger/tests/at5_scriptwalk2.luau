local fs = require("@lune/fs")
local Sandbox = require("../src/core/sandbox")

local result = Sandbox.run([[
	local t = { a = 1, b = 2 }
	local k, v = next(t, nil)
	print("plain:", k, v)
	local s = { x = workspace }
	local k2, v2 = next(s, nil)
	print("spyval:", k2, v2, type(v2))
]], { timeout = 30, maxExplored = 0 })

print("ok:", result.ok, "err:", tostring(result.err):sub(1, 300))
for _, entry in ipairs(result.outputs or {}) do
	print("out:", entry.text)
end
