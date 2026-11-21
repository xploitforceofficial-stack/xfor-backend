local Sandbox = require("../src/core/sandbox")

local r = Sandbox.run([[
print("A:", pcall(table.unpack, buffer.fromstring("ab"), 1, 10))
print("B:", pcall(function() return table.unpack({1,2}, 1, 10) end))
print("C:", pcall(buffer.tostring, buffer.fromstring("abc"), 1, 100))
print("D:", pcall(buffer.readstring, buffer.fromstring("abc"), 0, 100))
print("E:", pcall(string.sub, "ab", 5, 10))
]], { timeout = 20, maxExplored = 0 })
for _, e in ipairs(r.outputs or {}) do print(">", e.text) end
print("err:", r.err)
