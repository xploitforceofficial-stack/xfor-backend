local ok, roblox = pcall(require, "@lune/roblox")
if not ok then
	print("no @lune/roblox:", tostring(roblox))
	return
end
print("roblox lib keys sample:", tostring(roblox.Random))
local r = roblox.Random
if r == nil then

	local names = {}
	for k in pairs(roblox) do
		table.insert(names, tostring(k))
	end
	table.sort(names)
	print("datatypes:", table.concat(names, ", "))
	return
end
local gen = r.new(177465824)
print("v1", gen:NextNumber())
print("int", gen:NextInteger(189, 1164))
print("v3", gen:NextNumber())
print("v4", gen:NextNumber())
print("want v1 0.9598971928030796 v3 0.027539190730015265 v4 0.3377740061710911")
