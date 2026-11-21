local Sandbox = require("../src/core/sandbox")
local result = Sandbox.run([=[
local ok, err = pcall(function()
	local p = Instance.new("Part")
	p.Anchored = false
	p.Parent = workspace
	local fc = Instance.new("FloatCurve")
	print("fc:", fc ~= nil, tostring(fc and fc.ClassName))
	p.AssemblyLinearVelocity = Vector3.new(0, 10, 0)
	task.wait()
	print("vel type:", typeof(p.AssemblyLinearVelocity))
end)
print("body ok:", ok, "err:", tostring(err))
]=])
print("ok:", result.ok, "err:", tostring(result.err))
for _, line in ipairs(result.outputs or {}) do print("OUT:", line.text) end
