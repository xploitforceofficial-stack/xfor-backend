local fs = require("@lune/fs")
local Sandbox = require("../src/core/sandbox")

local source = fs.readFile("../Samples/Moonveli/v2.0.23/1.lua")

local ok, res = pcall(Sandbox.run, source, { timeout = 60, maxNest = 1 })
if not ok then
	print("sandbox failed:", res)
	return
end

local recs = res.trace and res.trace.records or {}
for _, r in ipairs(recs) do
	if r.kind == "note" and type(r.expression) == "string" then
		local e = r.expression
		if e:find("crash locals", 1, true) then
			print("=== locals ===")
			print(e:sub(1, 1600))
		elseif e:find("raised", 1, true) then
			print("=== raised ===")
			print(e:sub(1, 400))
		end
	end
end
