local Sandbox = require("../src/core/sandbox")
local fs = require("@lune/fs")
local src = fs.readFile("C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_polsec2.lua")
local result = Sandbox.run(src, { timeout = 120, maxExplored = 0 })
print("ok:", result.ok, "err:", tostring(result.err):sub(1, 120))
local records = (result.trace and result.trace.records) or {}
print("records:", #records)

for i = #records, 1, -1 do
	local r = records[i]
	if r.kind == "note" and type(r.expression) == "string" and r.expression:find("env call log") then
		print("=== ENV LOG TAIL:")
		print(r.expression:sub(#r.expression - 900))
		break
	end
end
