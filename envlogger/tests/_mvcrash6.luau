local Sandbox = require("../src/core/sandbox")

local r = Sandbox.run([[
local g = getfenv()
local gs = g.game.GetService
local rs = gs(g.game, "ReplicatedStorage")
print("via cached gs:", rs)
print("rs.Parent:", rs.Parent)
-- also: service fetched, method cached, called with dot syntax
local svc = game:GetService("ReplicatedStorage")
local pn = svc.Parent
print("dot Parent:", pn)
]], { timeout = 20, maxExplored = 0 })
for _, e in ipairs(r.outputs or {}) do print(">", e.text) end
print("err:", r.err)
