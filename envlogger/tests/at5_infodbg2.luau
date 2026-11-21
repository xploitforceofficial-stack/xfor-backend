local Sandbox = require("../src/core/sandbox")

local src = [[
local function n(fn) return tostring(select(3, debug.info(fn, "sln"))) end
local rs = game:GetService("RunService")
print("IsStudio", n(rs.IsStudio), "IsClient", n(rs.IsClient), "IsServer", n(rs.IsServer))
local et = Enum.HumanoidRigType
print("FromName", n(et.FromName), "FromValue", n(et.FromValue))
print("IsA", n(et.R6.IsA))
local rng = Random.new(1)
print("NextUnitVector", n(rng.NextUnitVector), "NextInteger", n(rng.NextInteger), "NextNumber", n(rng.NextNumber), "Shuffle", n(rng.Shuffle), "Clone", n(rng.Clone))
local sig = rs.Heartbeat
local conn = sig:Connect(function() end)
print("Connect", n(sig.Connect), "Disconnect", n(conn.Disconnect))
]]

local ok, res = pcall(Sandbox.run, src, { timeout = 30 })
if not ok then
	print("sandbox error:", res)
	return
end
print("ok:", res.ok, "err:", res.err)
for _, entry in ipairs(res.outputs or {}) do
	print("OUT|" .. tostring(entry.text))
end
