local fs = require("@lune/fs")
local Sandbox = require("../src/core/sandbox")

local source = fs.readFile("tests/at5_fixture.lua")

local result = Sandbox.run(source, { timeout = 120, maxExplored = 0 })

print("result.ok:", result.ok)
print("result.err:", tostring(result.err):sub(1, 200))
print("outputs:")
local n = 0
for _, entry in ipairs(result.outputs or {}) do
	n += 1
	print("  " .. tostring(entry.text))
end
print("total output lines:", n)
