local Sandbox = require("../src/core/sandbox")
local r = Sandbox.run([[
local hs = game:GetService("HttpService")
print(type(hs))
print(hs.JSONDecode)
print(pcall(function() return hs:JSONDecode("{}") end))
print(pcall(function() return hs.JSONDecode(hs, "{}") end))
print(pcall(function() return hs:JSONEncode({a=1}) end))
]], { timeout = 20, maxExplored = 0 })
for _, e in ipairs(r.outputs or {}) do print(">", e.text) end
print("err:", r.err)
