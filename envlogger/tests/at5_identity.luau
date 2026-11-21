local Sandbox = require("../src/core/sandbox")
local src = [[
local p = Instance.new("Folder")
local c = Instance.new("Folder")
print("same var|", tostring(p == p))
local alias = p
print("alias|", tostring(p == alias))
c.Parent = p
print("parent eq|", tostring(c.Parent == p))
print("parent type|", tostring(type(c.Parent)), tostring(typeof(c.Parent)))
print("p type|", tostring(type(p)), tostring(typeof(p)))
print("find eq|", tostring(p:FindFirstChild("Folder") == c))
local g1 = game
print("game eq|", tostring(game == g1))
local ws = workspace
print("workspace eq|", tostring(workspace == ws))
print("game.Workspace eq|", tostring(game.Workspace == workspace))
local svc = game:GetService("RunService")
local svc2 = game:GetService("RunService")
print("service eq|", tostring(svc == svc2))
print("rawget mt p|", tostring(getmetatable(p)))
print("mt c.Parent|", tostring(getmetatable(c.Parent)))
]]
local ok, res = pcall(Sandbox.run, src, { timeout = 60 })
if not ok then print("sandbox error:", res) return end
print("ok:", res.ok, "err:", res.err)
for _, e in ipairs(res.outputs or {}) do print("OUT|" .. tostring(e.text)) end
