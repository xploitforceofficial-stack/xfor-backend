local Sandbox = require("../src/core/sandbox")
local fs = require("@lune/fs")
local src = fs.readFile("C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_polsec2.lua")
local result = Sandbox.run(src, { timeout = 200, maxExplored = 0 })
local records = (result.trace and result.trace.records) or {}
for i, r in ipairs(records) do
	local d = r.detail
	local dtext = ""
	if type(d) == "table" then
		for k, v in pairs(d) do dtext ..= string.format(" %s=%s", k, tostring(v):sub(1, 50)) end
	end
	print(i, r.kind, tostring(r.expression):sub(1, 100), "|", dtext:sub(1, 150))
end
