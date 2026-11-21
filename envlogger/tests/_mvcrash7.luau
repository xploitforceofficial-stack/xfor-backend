local Sandbox = require("../src/core/sandbox")

local r = Sandbox.run([[
print("A:", Instance.new("WorldModel").Parent)
print("B:", Instance.new("Part").Parent)
local t = {}
print("C:", pcall(function() return (game:GetService("ReplicatedStorage")).Parent end))
print("D:", pcall(function()
	local m = game.GetService
	return m(game, "ReplicatedStorage").Parent
end))
]], { timeout = 20, maxExplored = 0 })
for _, e in ipairs(r.outputs or {}) do print(">", e.text) end
print("err:", r.err)
