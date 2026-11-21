local Sandbox = require("../src/core/sandbox")
local src = [[
local p = Instance.new("Folder")
local c = Instance.new("Folder")
c.Parent = p
print("c.Name|", tostring(c.Name))
print("p children#|", tostring(#p:GetChildren()))
print("FindFirstChild|", tostring(p:FindFirstChild("Folder")))
print("FindFirstChild by c.Name|", tostring(p:FindFirstChild(c.Name)))
print("FindFirstChildOfClass|", tostring(p:FindFirstChildOfClass("Folder")))
print("WaitForChild|", tostring(p:WaitForChild("Folder")))
c.Name = "zzz"
print("after rename FindFirstChild zzz|", tostring(p:FindFirstChild("zzz")))
print("p.zzz|", tostring(p.zzz))
print("childByIndex|", tostring(p:GetChildren()[1].Name))
]]
local ok, res = pcall(Sandbox.run, src, { timeout = 60 })
if not ok then print("sandbox error:", res) return end
print("ok:", res.ok, "err:", res.err)
for _, e in ipairs(res.outputs or {}) do print("OUT|" .. tostring(e.text)) end
