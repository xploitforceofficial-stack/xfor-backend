local Sandbox = require("../src/core/sandbox")

local r = Sandbox.run([[
local hs = game:GetService("HttpService")
local m = hs.JSONDecode
print("m type:", type(m))
local ok, res = pcall(m, hs, "{}")
print("direct-var call:", ok, res)
local ok2, res2 = pcall(function() return m(hs, '{"x":1}') end)
print("var call2:", ok2, res2)
]], { timeout = 20, maxExplored = 0 })
for _, e in ipairs(r.outputs or {}) do print(">", e.text) end
print("err:", r.err)
