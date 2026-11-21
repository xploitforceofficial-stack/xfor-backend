local Sandbox = require("../src/core/sandbox")
local fs = require("@lune/fs")
local src = fs.readFile("C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_mv_rob.lua")
local result = Sandbox.run(src, { timeout = 100, maxExplored = 0 })
local records = (result.trace and result.trace.records) or {}
for i, r in ipairs(records) do
	if r.kind == "note" and type(r.expression) == "string" and r.expression:find("env call log") then
		local text = r.expression
		print("=== LAST 1000 CHARS OF ENV LOG:")
		print(text:sub(#text - 1000))
	end
end
