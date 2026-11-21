local fs = require("@lune/fs")
local Sandbox = require("../src/core/sandbox")

local source = fs.readFile("tests/at5_fixture.lua")
local result = Sandbox.run(source, { timeout = 120, maxExplored = 0 })

local n = 0
for _, record in ipairs(result.trace.records) do
	n += 1
	if n <= 15 then
		print(record.kind, tostring(record.expression or record.text or ""):sub(1, 160))
	end
end
print("total records:", n)
