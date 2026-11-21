local Sandbox = require("../src/core/sandbox")
local src = [[
local folder = Instance.new("Folder")
local child = Instance.new("Folder")
child.Parent = folder
local sig = child.Changed
local conn = sig:Connect(function() end)
local rs = game:GetService("RunService")
local rnd = Random.new(1)
local cases = {
	{ "coroutine.create()", function() return coroutine.create() end },
	{ "coroutine.resume()", function() return coroutine.resume() end },
	{ "coroutine.wrap()", function() return coroutine.wrap() end },
	{ "coroutine.status()", function() return coroutine.status() end },
	{ "task.cancel()", function() return task.cancel() end },
	{ "task.spawn()", function() return task.spawn() end },
	{ "task.defer()", function() return task.defer() end },
	{ "task.delay()", function() return task.delay() end },
	{ "task.wait({})", function() return task.wait({}) end },
	{ "loadstring()", function() return loadstring() end },
	{ "Instance.new(nil)", function() return Instance.new(nil) end },
	{ "Path2DControlPoint.new(nil)", function() return Path2DControlPoint.new(nil) end },
	{ "Random.new({})", function() return Random.new({}) end },
	{ "conn.Disconnect(nil)", function() return conn.Disconnect(nil) end },
	{ "child.WaitForChild(nil)", function() return child.WaitForChild(nil) end },
	{ "rs.IsStudio(nil)", function() return rs.IsStudio(nil) end },
	{ "rs.IsClient(nil)", function() return rs.IsClient(nil) end },
	{ "rs.IsServer(nil)", function() return rs.IsServer(nil) end },
	{ "game.GetChildren(nil)", function() return game.GetChildren(nil) end },
	{ "folder:WaitForChild('x')", function() return folder:WaitForChild("nope_xyz", 0.1) end },
	{ "rnd:NextNumber()", function() return rnd:NextNumber() end },
	{ "rnd:NextInteger()", function() return rnd:NextInteger() end },
	{ "f:id", function() return child.Parent:WaitForChild(child.Name) == child end },
}
for _, case in ipairs(cases) do
	local ok, err = pcall(case[2])
	print(case[1] .. "|", tostring(ok), "|", tostring(err))
end
child:Destroy()
local okP, errP = pcall(function() child.Parent = folder end)
print("destroyed-parent|", tostring(okP), "|", tostring(errP))
print("conn.Connected|", tostring(conn.Connected))
]]
local ok, res = pcall(Sandbox.run, src, { timeout = 60 })
if not ok then print("sandbox error:", res) return end
print("ok:", res.ok, "err:", res.err)
for _, e in ipairs(res.outputs or {}) do print("OUT|" .. tostring(e.text)) end
