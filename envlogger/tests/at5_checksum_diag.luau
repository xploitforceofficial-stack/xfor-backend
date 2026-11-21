local fs = require("@lune/fs")
local Sandbox = require("../src/core/sandbox")

local source = fs.readFile("Samples/antitamperfound.lua")

local result = Sandbox.run(source, { timeout = 180, maxExplored = 0 })
print("err:", result.err)
for _, o in ipairs(result.outputs or {}) do
	print("OUT:", (o.text:gsub("%c+$", "")))
end
