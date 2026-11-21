local fs = require("@lune/fs")
local Sandbox = require("../src/core/sandbox")

local result = Sandbox.run([[
	local a = getfenv
	local b = getfenv
	local c = _G.getfenv
	print("a==b:", a == b, "a==c:", a == c)
	print("type:", type(a), typeof(a))
	print("info a n:", debug.info(a, "n"), "info a sln:", debug.info(a, "sln"))
	print("yieldable/comparing:", a == setfenv)
]], { timeout = 30, maxExplored = 0 })

print("ok:", result.ok, "err:", tostring(result.err):sub(1, 200))
for _, e in ipairs(result.outputs or {}) do print("out:", e.text) end
