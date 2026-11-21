local fs = require("@lune/fs")
local Sandbox = require("../src/core/sandbox")

local result = Sandbox.run([[
	local t2 = { script = script }
	local k, v = next(t2, nil)
	print("walk1:", k, v, type(v))
	local k2, v2 = next(t2, k)
	print("walk2:", k2, v2)
]], { timeout = 30, maxExplored = 0 })

print("ok:", result.ok, "err:", tostring(result.err):sub(1, 200))
for _, entry in ipairs(result.outputs or {}) do
	print("out:", entry.text)
end
