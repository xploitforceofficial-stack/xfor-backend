local fs = require("@lune/fs")
local Sandbox = require("../src/core/sandbox")

local source = fs.readFile("../Samples/Moonveli/v2.0.23/1.lua")

local ok, res = pcall(Sandbox.run, source, { timeout = 60, maxNest = 1 })
if not ok then
	print("sandbox failed:", res)
	return
end

for _, r in ipairs(res.trace and res.trace.records or {}) do
	if r.kind == "note" and tostring(r.expression):find("crash", 1, true) then
		print(r.expression:sub(1, 900))
		print("=====")
	end
end
