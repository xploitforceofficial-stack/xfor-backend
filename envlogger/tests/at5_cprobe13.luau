local fs = require("@lune/fs")
local Sandbox = require("../src/core/sandbox")

local result = Sandbox.run([[
	print("loadstring:", debug.info(loadstring, "sln"), "isC:", iscclosure(loadstring), "isL:", islclosure(loadstring))
	print("load:", debug.info(load, "sln"), "isC:", iscclosure(load))
	print("traceback:", debug.info(debug.traceback, "sln"), "isC:", iscclosure(debug.traceback))
	print("info fn:", debug.info(debug.info, "sln"), "isC:", iscclosure(debug.info))
]], { timeout = 30, maxExplored = 0 })

print("ok:", result.ok, "err:", tostring(result.err):sub(1, 200))
for _, e in ipairs(result.outputs or {}) do print("out:", e.text) end
