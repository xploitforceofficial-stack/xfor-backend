local Sandbox = require("../src/core/sandbox")

local r = Sandbox.run([[
local svc = game:GetService("HttpService")
-- indirect access like a VM register juggling:
local t = {}
t.f = function() return svc end
print("1:", type(t.f()))
print("2:", type(t.f().JSONDecode))
print("3:", pcall(function() return t.f():JSONDecode("{}") end))
-- the fatal pattern: method extracted once, receiver swapped
local m = svc.JSONDecode
local recv = game:GetService("HttpService")
print("4:", pcall(m, recv, "{}"))
-- what if receiver is the SPY itself re-fetched through getfenv
local g = getfenv()
print("5:", pcall(g.game.GetService, g.game, "HttpService"))
local hs2 = g.game:GetService("HttpService")
print("6:", type(hs2), pcall(function() return hs2:JSONDecode('{"k":2}') end))
]], { timeout = 20, maxExplored = 0 })
for _, e in ipairs(r.outputs or {}) do print(">", e.text) end
print("err:", r.err)
