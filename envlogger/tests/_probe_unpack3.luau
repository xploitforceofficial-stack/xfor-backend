local Sandbox = require("../src/core/sandbox")
local r = Sandbox.run([[
local b = buffer.fromstring("hello")
print("A:", pcall(unpack, b, 1, 3))
print("B:", pcall(unpack, buffer.create(2), 1, 8))
]], { timeout = 20, maxExplored = 0 })
for _, e in ipairs(r.outputs or {}) do print(">", e.text) end
print("err:", r.err)
