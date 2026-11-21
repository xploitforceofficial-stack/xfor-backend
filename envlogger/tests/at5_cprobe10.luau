local fs = require("@lune/fs")
local Sandbox = require("../src/core/sandbox")

local result = Sandbox.run([[
	local names = { "getfenv", "setfenv", "getmetatable", "next", "rawget" }
	for _, n in ipairs(names) do
		local v = _G[n]
		print(n, type(v), tostring(v):sub(1, 40))
	end
]], { timeout = 30, maxExplored = 0 })

print("ok:", result.ok, "err:", tostring(result.err):sub(1, 200))
for _, e in ipairs(result.outputs or {}) do print("out:", e.text) end
