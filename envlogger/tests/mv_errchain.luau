local fs = require("@lune/fs")
local Sandbox = require("../src/core/sandbox")

local source = fs.readFile("../Samples/Moonveli/v2.0.23/1.lua")

local ok, res = pcall(Sandbox.run, source, { timeout = 60, maxNest = 1 })
if not ok then
	print("sandbox failed:", res)
	return
end

for i, r in ipairs(res.trace and res.trace.records or {}) do
	if r.kind == "error" then
		print("error record", i)
		print("  expression:", tostring(r.expression):sub(1, 200))
		if r.detail then
			for k, v in pairs(r.detail) do
				print("  detail." .. tostring(k) .. ":", tostring(v):sub(1, 300))
			end
		end
	end
end
