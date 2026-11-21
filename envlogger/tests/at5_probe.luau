local fs = require("@lune/fs")
local Sandbox = require("../src/core/sandbox")

local source = fs.readFile("../envlogger/Samples/antitamperfound.lua")

local result = Sandbox.run(source, { timeout = 120, maxExplored = 0 })

print("result.ok:", result.ok)
print("result.err:", tostring(result.err):sub(1, 400))
print("outputs:")
local n = 0
for _, entry in ipairs(result.outputs or {}) do
	n += 1
	if n <= 80 then
		print("  " .. tostring(entry.text))
	end
end
print("total output lines:", n)
if result.traceback then
	print("traceback:", tostring(result.traceback):sub(1, 600))
end
