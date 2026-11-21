local Sandbox = require("../src/core/sandbox")
local src = [[
local p = Instance.new("Folder")
local c = Instance.new("Folder")
c.Parent = p
local f1 = p:FindFirstChild("Folder")
local f2 = p:FindFirstChild("Folder")
print("f1==c|", tostring(f1 == c), "f1==f2|", tostring(f1 == f2), "raweq|", tostring(rawequal(f1, c)))
print("f1 name|", tostring(f1 and f1.Name))
print("f1 path|", tostring(typeof(f1)))
local kids = p:GetChildren()
print("kids#|", tostring(#kids), "kid==c|", tostring(kids[1] == c), "raweq|", tostring(rawequal(kids[1], c)))
print("getchildren twice eq|", tostring(p:GetChildren()[1] == kids[1]))
]]
local ok, res = pcall(Sandbox.run, src, { timeout = 60 })
if not ok then print("sandbox error:", res) return end
print("ok:", res.ok, "err:", res.err)
for _, e in ipairs(res.outputs or {}) do print("OUT|" .. tostring(e.text)) end
