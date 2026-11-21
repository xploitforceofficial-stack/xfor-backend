local fs = require("@lune/fs")
local Sandbox = require("../src/core/sandbox")

local source = fs.readFile("../Samples/Moonveli/v2.0.23/1.lua")

local ok, res = pcall(Sandbox.run, source, { timeout = 60, maxNest = 1 })
if not ok then
	print("sandbox failed:", res)
	return
end

local recs = res.trace and res.trace.records or {}
local notes = 0
for _, r in ipairs(recs) do
	if r.kind == "note" and type(r.expression) == "string" then
		local e = r.expression
		if e:find("crash", 1, true) then
			notes += 1
			print("=== crash note " .. notes .. " ===")
			print(e:sub(1, 1200))
		end
	end
end
print("crash notes total:", notes)
