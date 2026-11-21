local Sandbox = require("../src/core/sandbox")
local fs = require("@lune/fs")
local src = fs.readFile("C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_polsec2.lua")
local result = Sandbox.run(src, { timeout = 60, maxExplored = 0 })
print("60s:", "ok=" .. tostring(result.ok), "dec=" .. tostring(result.decryptedStringCount))
local records = (result.trace and result.trace.records) or {}
for i = #records, 1, -1 do
	local r = records[i]
	if r.kind == "note" and type(r.expression) == "string" and r.expression:find("env call log") then
		print(r.expression:sub(#r.expression - 500))
		break
	end
end
