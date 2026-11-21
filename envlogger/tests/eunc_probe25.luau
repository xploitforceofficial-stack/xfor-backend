local Roblox = require("../src/env/roblox")
local built = Roblox.build({
	trace = nil, nest = 0, config = {},
	checkBudget = function() return false end,
	onHostile = function() end,
	clock = { elapsed = 0 }, taskState = nil, macros = nil,
})
local Enum = built.Enum

print("rawget GetEnums:", rawget(Enum, "GetEnums"))
print("rawget AccessModifierType:", rawget(Enum, "AccessModifierType"))
print("index GetEnums:", Enum.GetEnums)

local mt = getmetatable(Enum)
if type(mt) == "table" then
	print("mt fields:", mt.GetEnums ~= nil, mt.__index ~= nil, mt.__metatable)
else
	print("mt:", tostring(mt))
end
