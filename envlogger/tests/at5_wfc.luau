local Sandbox = require("../src/core/sandbox")
local src = [[
local folder = Instance.new("Folder")
local child = Instance.new("Folder")
child.Parent = folder
child.Name = "847283502"
print("child.Name|", tostring(child.Name))
print("folder:GetChildren()#|", tostring(#folder:GetChildren()))
print("folder:FindFirstChild(name)|", tostring(folder:FindFirstChild("847283502") == child))
print("folder:WaitForChild(name)|", tostring(folder:WaitForChild("847283502") == child))
print("folder.Child|", tostring(folder:FindFirstChild("847283502")))
print("parent ok|", tostring(child.Parent == folder))
]]
local ok, res = pcall(Sandbox.run, src, { timeout = 60 })
if not ok then print("sandbox error:", res) return end
print("ok:", res.ok, "err:", res.err)
for _, e in ipairs(res.outputs or {}) do print("OUT|" .. tostring(e.text)) end
