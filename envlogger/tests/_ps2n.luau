local Sandbox = require("../src/core/sandbox")
local fs = require("@lune/fs")
local src = fs.readFile("C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_polsec2.lua")
local result = Sandbox.run(src, { timeout = 200, maxExplored = 0 })
local records = (result.trace and result.trace.records) or {}
print("records:", #records)
for i, r in ipairs(records) do
	if r.kind == "error" or (r.kind == "note" and type(r.expression) == "string" and r.expression:find("env call")) then
		local text = tostring(r.expression)
		print(i, r.kind, text:sub(#text - 700))
	end
end
