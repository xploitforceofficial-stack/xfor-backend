local Sandbox = require("../src/core/sandbox")

local src = [[
local values = {
    Vector3.new(1, 2, 3),
    Vector2.new(1, 2),
    CFrame.new(1, 2, 3),
    Color3.fromRGB(1, 2, 3),
    UDim2.new(0, 1, 0, 2),
    Rect.new(0, 0, 1, 1),
    NumberRange.new(1, 2),
    Random.new(1),
    Instance.new("Folder"),
    Enum.Material.Plastic,
    Enum.Material,
    game:GetService("Players"),
    workspace,
    TweenInfo.new(1),
    Ray.new(Vector3.new(0, 0, 0), Vector3.new(1, 0, 0)),
    PhysicalProperties.new(1, 1, 1, 1, 1),
}
for _, v in ipairs(values) do
    print(typeof(v), "=>", tostring(v))
end
print("empty instance:", tostring(Instance.new("Folder")))
print("bool/num/nil:", tostring(true), tostring(1), tostring(nil))
]]

local result = Sandbox.run(src, { timeout = 60, maxExplored = 0 })
print("ok:", result.ok, "err:", tostring(result.err):sub(1, 140))
for _, entry in ipairs(result.outputs or {}) do
	print("  " .. tostring(entry.text))
end
