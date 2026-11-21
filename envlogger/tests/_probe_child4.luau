local Sandbox = require("../src/core/sandbox")

local r = Sandbox.run([[
print("game.Parent:", game.Parent)
print("script.Parent.Parent:", script.Parent and script.Parent.Parent)
-- but maybe: the VM helper k.d returns nil for unknown enum etc
print("workspace.Parent:", workspace.Parent)
-- Chunk-level: game:GetService('Workspace').Parent.ClassName
print("chain:", game:GetService("Workspace").Parent.ClassName)
]], { timeout = 20, maxExplored = 0 })
for _, e in ipairs(r.outputs or {}) do print(">", e.text) end
print("err:", r.err)
