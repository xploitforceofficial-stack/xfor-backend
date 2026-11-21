local Sandbox = require("../src/core/sandbox")

local r = Sandbox.run([[
local w = Instance.new("WorldModel")
print("w.Parent:", w.Parent)
local rs = game:GetService("ReplicatedStorage")
print("rs:", rs, "rs.Parent:", rs.Parent)
print("rs.ClassName:", rs.ClassName)
print("rs.Name:", rs.Name)
]], { timeout = 20, maxExplored = 0 })
for _, e in ipairs(r.outputs or {}) do print(">", e.text) end
print("err:", r.err)
