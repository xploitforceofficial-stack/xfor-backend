local Sandbox = require("../src/core/sandbox")
local fs = require("@lune/fs")
local src = fs.readFile("C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_polsec2.lua")
local function runFor(t)
	local result = Sandbox.run(src, { timeout = t, maxExplored = 0 })
	local records = (result.trace and result.trace.records) or {}
	for i = #records, 1, -1 do
		local r = records[i]
		if r.kind == "note" and type(r.expression) == "string" and r.expression:find("env call log") then
			local first = r.expression:match("string%.sub%(s.-, n(%d+),")
			local total = r.expression:match("last %d+/(%d+)")
			local decs = 0
			for _ in r.expression:gmatch("string%.char") do decs += 1 end
			return first, total, decs
		end
	end
	return nil
end
local f1, t1, d1 = runFor(12)
print("12s: first-idx=" .. tostring(f1) .. " total=" .. tostring(t1) .. " chars-in-window=" .. tostring(d1))
local f2, t2, d2 = runFor(25)
print("25s: first-idx=" .. tostring(f2) .. " total=" .. tostring(t2) .. " chars-in-window=" .. tostring(d2))
