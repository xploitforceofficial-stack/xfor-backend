local fs = require("@lune/fs")

local source = fs.readFile("../Samples/PSU/v5/1.lua")

local function tryFrom(pos: number): string?
	local tail = source:sub(pos)
	local f, e = loadstring("return function(...) " .. tail .. " end")
	if f then return nil end
	return (e:gsub("\n", " "))
end

local probes = { 1, 1000484, 1000532, 1001000, 1002000, 1003000, 1003915, 1003920, 1004000, 1018514, 1018519, 1020000 }

for _, pos in ipairs(probes) do
	local err = tryFrom(pos)
	if err then
		print(("%8d  %s"):format(pos, err:sub(1, 90)))
	else
		print(("%8d  OK"):format(pos))
	end
end
