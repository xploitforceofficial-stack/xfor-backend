local Sandbox = require("../src/core/sandbox")

local r = Sandbox.run([[
print("A:", pcall(unpack, "abc", 1, 10))
print("B:", pcall(table.unpack, {1,2}, 1, 10))
print("C:", pcall(unpack, "abc"))
print("D:", pcall(unpack, "abc", 2, 1))
]], { timeout = 20, maxExplored = 0 })
for _, e in ipairs(r.outputs or {}) do print(">", e.text) end
print("err:", r.err)
