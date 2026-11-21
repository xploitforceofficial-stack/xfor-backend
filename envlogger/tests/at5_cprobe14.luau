local fs = require("@lune/fs")
local Sandbox = require("../src/core/sandbox")

local result = Sandbox.run([[
	local n = select("#", debug.info(loadstring, "sln"))
	print("count sln:", n)
	local a, b, c = debug.info(loadstring, "sln")
	print("vals:", tostring(a), tostring(b), tostring(c))
	local n2 = select("#", debug.info(loadstring, "slnaf"))
	print("count slnaf:", n2)
	local n3 = select("#", debug.info(getmetatable, "slnaf"))
	print("count gm slnaf:", n3)
	print("loadstring isC:", iscclosure(loadstring), "isL:", islclosure(loadstring))
	print("gm isC:", iscclosure(getmetatable))
]], { timeout = 30, maxExplored = 0 })

print("ok:", result.ok, "err:", tostring(result.err):sub(1, 200))
for _, e in ipairs(result.outputs or {}) do print("out:", e.text) end
