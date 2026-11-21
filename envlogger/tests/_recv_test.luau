local Sandbox = require("../src/core/sandbox")
local src = [==[
local p = Instance.new("Path2D")
print("type", typeof(p), tostring(p))
local ok, e = pcall(function() return p:SetControlPoints({}) end)
print("call", ok, tostring(e))
-- nil receiver case
local n = nil
local ok2, e2 = pcall(function() return n:SetControlPoints({}) end)
print("nilrecv", ok2, tostring(e2))
-- Position on various things
local cam = workspace.CurrentCamera
print("cam", cam ~= nil)
if cam then print("camPos", tostring(cam.Position)) end
local hrp = workspace:FindFirstChild("HumanoidRootPart") or workspace:FindFirstChildOfClass("Humanoid")
print("hrp", hrp)
]==]
local r = Sandbox.run(src, { timeout = 15, allowHttp = false, maxExplored = 0, softInstanceCall = true })
print("err", tostring(r.err))
for _, rec in ipairs(r.trace.records) do
  if rec.kind == "output" then print("OUT", tostring(rec.expression)) end
end
