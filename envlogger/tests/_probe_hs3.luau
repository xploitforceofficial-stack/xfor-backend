local Sandbox = require("../src/core/sandbox")

local r = Sandbox.run([[
local function retfn() return function() end end
local ok, err = pcall(function()
    local f = retfn()
    return f.JSONDecode
end)
print("fn member:", ok, err)
-- what about getfenv-based access
local g = getfenv()
print("g.HttpService:", g.HttpService)
print("g.game:", type(g.game))
local hs = g.game:GetService("HttpService")
print("indirect service:", type(hs))
]], { timeout = 20, maxExplored = 0 })
for _, e in ipairs(r.outputs or {}) do print(">", e.text) end
print("err:", r.err)
