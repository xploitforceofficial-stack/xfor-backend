local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Sandbox = require("../src/core/sandbox")
local source = fs.readFile("tests/at5_fixture_all.lua")
local result = Sandbox.run(source, { timeout = 180, maxExplored = 0 })
for k, v in pairs(result) do
	if k ~= "outputs" then
		local ok, s = pcall(serde.encode, v)
		print("KEY", k, ok and tostring(s):sub(1, 600) or tostring(v):sub(1, 600))
	end
end
print("--- outputs:")
for _, entry in ipairs(result.outputs or {}) do print("OUT|" .. tostring(entry.text)) end
