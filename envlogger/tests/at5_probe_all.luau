local fs = require("@lune/fs")
local Sandbox = require("../src/core/sandbox")
local source = fs.readFile("tests/at5_fixture_all.lua")
local result = Sandbox.run(source, { timeout = 180, maxExplored = 0 })
print("ok:", result.ok, "err:", tostring(result.err):sub(1, 300))
for _, entry in ipairs(result.outputs or {}) do
	print("OUT|" .. tostring(entry.text))
end
