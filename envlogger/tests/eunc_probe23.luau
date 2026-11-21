local Roblox = require("../src/env/roblox")
local built = Roblox.build({
	trace = nil,
	nest = 0,
	config = {},
	checkBudget = function() return false end,
	onHostile = function() end,
	clock = { elapsed = 0 },
	taskState = nil,
	macros = nil,
})
print("Enum type:", typeof(built.Enum))
print("GetEnums:", tostring(built.Enum.GetEnums))
local mt = debug and rawget or nil
print("cat:", tostring(built.Enum.AccessModifierType ~= nil))
