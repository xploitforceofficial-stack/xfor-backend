local Sandbox = require("../src/core/sandbox")

local r = Sandbox.run([[
local g = getfenv()
print("g.script:", g.script, type(g.script))
print("g.script.Parent:", g.script and g.script.Parent)
print("g.script.Parent.ClassName:", g.script and g.script.Parent and g.script.Parent.ClassName)
-- common safeenv: local env = getfenv(); local s = env.script; s.Parent.Name
print("parent name:", g.script and g.script.Parent and g.script.Parent.Name)
]], { timeout = 20, maxExplored = 0 })
for _, e in ipairs(r.outputs or {}) do print(">", e.text) end
print("err:", r.err)
