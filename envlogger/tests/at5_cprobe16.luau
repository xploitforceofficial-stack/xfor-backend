local fs = require("@lune/fs")
local Sandbox = require("../src/core/sandbox")

local result = Sandbox.run([[
	local folder = Instance.new("Folder")
	local fn = folder.WaitForChild
	print("type:", type(fn), "typeof:", typeof(fn), "count:", select("#", debug.info(fn, "sln")))
	local a, b, c = debug.info(fn, "sln")
	print("vals:", tostring(a), tostring(b), tostring(c))
	print("count slnaf:", select("#", debug.info(fn, "slnaf")))
	local n = select("#", debug.info(loadstring, "sln"))
	print("loadstring count:", n)
]], { timeout = 30, maxExplored = 0 })

print("ok:", result.ok, "err:", tostring(result.err):sub(1, 200))
for _, e in ipairs(result.outputs or {}) do print("out:", e.text) end
