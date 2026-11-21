local fs = require("@lune/fs")
local Sandbox = require("../src/core/sandbox")

local result = Sandbox.run([[
	-- which getmetatable do we have?
	print("direct:", debug.info(getmetatable, "sln"))
	print("string.byte:", debug.info(string.byte, "sln"))
	print("tostring:", debug.info(tostring, "sln"))
]], { timeout = 30, maxExplored = 0 })

print("ok:", result.ok, "err:", tostring(result.err):sub(1, 200))
for _, e in ipairs(result.outputs or {}) do print("out:", e.text) end
