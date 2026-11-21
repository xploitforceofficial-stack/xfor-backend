local Sandbox = require("../src/core/sandbox")
local fs = require("@lune/fs")
local src = fs.readFile("C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_polsec2.lua")
local result = Sandbox.run(src, { timeout = 30, maxExplored = 0 })
local records = (result.trace and result.trace.records) or {}
for i = #records, 1, -1 do
	local r = records[i]
	if r.kind == "note" and type(r.expression) == "string" and r.expression:find("env call log") then

		local idxs = {}
		for num in r.expression:gmatch("string%.sub%(s.-, n(%d+), n(%d+)%)") do
			idxs[#idxs+1] = num
		end
		print("sample decode idx:", table.concat(idxs, ","))
		break
	end
end
