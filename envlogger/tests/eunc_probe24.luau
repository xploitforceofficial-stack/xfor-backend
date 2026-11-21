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
local Enum = built.Enum
print("GetEnums:", tostring(Enum.GetEnums))
print("BogusCat:", tostring(Enum.BogusCat_eunc))
print("AccessModifierType:", tostring(Enum.AccessModifierType ~= nil))

print("hasCategory check via category fetch:", typeof(Enum.AccessModifierType))
