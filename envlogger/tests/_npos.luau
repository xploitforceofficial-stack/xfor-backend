local Sandbox = require("../src/core/sandbox")
local src = [==[
local lp = game:GetService("Players").LocalPlayer
print("lp", lp)
print("char", lp.Character)
if lp.Character then print("hrp", lp.Character:FindFirstChild("HumanoidRootPart")) end
print("cam", workspace.CurrentCamera)
print("camPos2", workspace.CurrentCamera and workspace.CurrentCamera.Position)
-- nil then Position pattern
local a = nil
local ok, e = pcall(function() return a.Position end)
print("nilPos", ok, tostring(e))
]==]
local r = Sandbox.run(src, { timeout = 10, softInstanceCall = true })
print("err", tostring(r.err))
for _, rec in ipairs(r.trace.records) do
  if rec.kind == "output" then print("OUT", tostring(rec.expression)) end
end
