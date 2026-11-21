local fs = require("@lune/fs")
local Sandbox = require("../src/core/sandbox")

local result = Sandbox.run([[
	local folder = Instance.new("Folder")
	for _, n in ipairs({ "WaitForChild", "Clone", "FindFirstChild", "GetChildren", "Connect" }) do
		local ok, fn = pcall(function() return folder[n] end)
		if ok and fn ~= nil then
			print(n, debug.info(fn, "sln"), "isC:", iscclosure(fn))
		else
			print(n, "missing", tostring(fn))
		end
	end
]], { timeout = 30, maxExplored = 0 })

print("ok:", result.ok, "err:", tostring(result.err):sub(1, 200))
for _, e in ipairs(result.outputs or {}) do print("out:", e.text) end
