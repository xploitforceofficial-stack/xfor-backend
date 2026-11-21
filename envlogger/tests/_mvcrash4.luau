local Sandbox = require("../src/core/sandbox")
local fs = require("@lune/fs")
local src = fs.readFile("C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_mv_rob.lua")
local result = Sandbox.run(src, { timeout = 100, maxExplored = 0 })
local records = (result.trace and result.trace.records) or {}

for i, r in ipairs(records) do
	if i >= 10 then
		local d = r.detail
		local dtext = ""
		if type(d) == "table" then
			for k, v in pairs(d) do dtext ..= string.format(" %s=%s", k, tostring(v):sub(1, 80)) end
		end
		print(i, r.kind, tostring(r.expression):sub(1, 110), "|", dtext:sub(1, 200))
	end
end
