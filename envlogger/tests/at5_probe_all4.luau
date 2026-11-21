local fs = require("@lune/fs")
local Sandbox = require("../src/core/sandbox")
local source = fs.readFile("tests/at5_fixture_all.lua")
local result = Sandbox.run(source, { timeout = 180, maxExplored = 0 })
print("err:", result.err)
local trace = result.trace
print("trace type:", type(trace))
if type(trace) == "table" then
	for i, entry in ipairs(trace) do
		local parts = {}
		if type(entry) == "table" then
			for k, v in pairs(entry) do
				parts[#parts + 1] = tostring(k) .. "=" .. tostring(v):sub(1, 120)
			end
		else
			parts[#parts + 1] = tostring(entry)
		end
		print("F" .. i .. "| " .. table.concat(parts, " | "))
	end
end
