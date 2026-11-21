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
local kinds: { [string]: number } = {}
for _, r in ipairs(recs) do
	kinds[r.kind] = (kinds[r.kind] or 0) + 1
end
for k, n in pairs(kinds) do
	print("kind", k, n)
end
print("--- last 20 records ---")
local start = math.max(1, #recs - 20)
for i = start, #recs do
	local r = recs[i]
	local text = tostring(r.expression):gsub("%c", " ")
	print(i, r.kind, text:sub(1, 150))
end
