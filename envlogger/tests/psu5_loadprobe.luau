local fs = require("@lune/fs")

local source = fs.readFile("../Samples/PSU/v5/1.lua")

local fn, err = loadstring(source)
if fn then
	print("LOADS OK in Luau!")
else
	print("loadstring failed:", err)
end

local candidates = {
	{ 1000484, "after junk run" },
	{ 1000532, "local function o" },
	{ 1000525, "_(PSU..." },
	{ 1000531, "before _(PSU" },
}

for _, c in ipairs(candidates) do
	local pos, label = c[1], c[2]
	local tail = source:sub(pos)
	local f2, e2 = loadstring("return function(...) " .. tail .. " end")
	if f2 then
		print(("%d (%s): tail+wrap LOADS OK"):format(pos, label))
	else
		print(("%d (%s): %s"):format(pos, label, (e2:gsub("\n", " "))))
	end
end
