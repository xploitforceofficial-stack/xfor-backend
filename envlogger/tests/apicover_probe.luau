local Sandbox = require("../src/core/sandbox")

local src = [[
local frame = Instance.new("Frame")
print("Frame:IsA GuiObject =", frame:IsA("GuiObject"))
print("Frame:IsA Instance =", frame:IsA("Instance"))
print("Frame:IsA BasePart =", frame:IsA("BasePart"))
print("Frame.ClassName =", frame.ClassName)
print("Part:IsA BasePart =", Instance.new("Part"):IsA("BasePart"))
print("TextButton:IsA GuiButton =", Instance.new("TextButton"):IsA("GuiButton"))
print("Path2D ok =", pcall(function() return Instance.new("Path2D") end))
print("Path2DControlPoint ok =", pcall(function() return Path2DControlPoint.new(UDim2.new(), UDim2.new(), UDim2.new()) end))
print("GuiObject rejected =", pcall(function() return Instance.new("GuiObject") end))
print("Workspace rejected =", pcall(function() return Instance.new("Workspace") end))
print("Known enums:", Enum.KeyCode.A.Value, Enum.Material.Plastic.Value, Enum.Font.Code.Value)
print("Unknown enum =", tostring(Enum.DefinitelyNotAnEnum))
print("Unknown item =", tostring(Enum.Material.DefinitelyNotAnItem))
print("Material items =", #Enum.Material:GetEnumItems())
print("KeyCode items =", #Enum.KeyCode:GetEnumItems())
print("FromName =", Enum.Material:FromName("Plastic").Value)
print("FromName fake =", tostring(Enum.Material:FromName("Nope")))
print("service =", game:GetService("AdService") ~= nil)
print("service2 =", game:GetService("VideoService") ~= nil)
print("service3 =", game:GetService("StudioService") ~= nil)
]]

local result = Sandbox.run(src, { timeout = 60, maxExplored = 0 })
print("ok:", result.ok, "err:", tostring(result.err):sub(1, 160))
for _, entry in ipairs(result.outputs or {}) do
	print("  " .. tostring(entry.text))
end
