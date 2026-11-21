local Sandbox = require("../src/core/sandbox")
local r = Sandbox.run([[
local thing = game:GetService("ReplicatedStorage").SomeRandomThing
print("type:", typeof(thing), type(thing))
print("pcall Parent:", pcall(function() return thing.Parent end))
print("direct:", thing.Parent)
]], { timeout = 20, maxExplored = 0 })
for _, e in ipairs(r.outputs or {}) do print(">", e.text) end
print("err:", r.err)
