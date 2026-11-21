local Sandbox = require("../src/core/sandbox")
local r = Sandbox.run([[
-- unknown service property (not method, not child in our fake place)
print("A:", pcall(function() return game:GetService("ReplicatedStorage").SomeRandomThing end))
-- unknown service child name via dot
print("B:", game:GetService("ReplicatedStorage").SomeFolder)
-- unknown game child
print("C:", pcall(function() return game.SomeRandomService end))
print("D:", pcall(function() return workspace.RandomPart end))
]], { timeout = 20, maxExplored = 0 })
for _, e in ipairs(r.outputs or {}) do print(">", e.text) end
print("err:", r.err)
