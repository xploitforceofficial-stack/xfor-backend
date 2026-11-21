local fs = require("@lune/fs")
local Sandbox = require("../src/core/sandbox")

local source = fs.readFile("../Samples/Moonveli/v2.0.23/1.lua")

local ok, res = pcall(Sandbox.run, source, { timeout = 60, maxNest = 1 })
if not ok then
	print("sandbox failed:", res)
	return
end

local recs = res.trace and res.trace.records or {}
print("total records:", #recs)
local start = math.max(1, #recs - 14)
for i = start, #recs do
	local r = recs[i]
	local text = tostring(r.expression):gsub("%c", " ")
	print(i, r.kind, text:sub(1, 160))
end
