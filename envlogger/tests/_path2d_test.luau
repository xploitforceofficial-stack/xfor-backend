local Sandbox = require("../src/core/sandbox")
local src = [==[
local g = Instance.new("Path2D")
print("got", g)
local ok, err = pcall(function() g:SetControlPoints({}) end)
print("SetControlPoints", ok, err)
local ok2, cps = pcall(function() return g:GetControlPoints() end)
print("GetControlPoints", ok2, cps)
local ok3, p = pcall(function() return g + 1 end)
print("path+1", ok3, p)
local ok4 = pcall(function() return game + 1 end)
print("game+1 soft", ok4, _)
]==]
local r = Sandbox.run(src, { timeout = 15, allowHttp = false, maxExplored = 0, softInstanceCall = true })
print("err", tostring(r.err))
for _, rec in ipairs(r.trace.records) do
  if rec.kind == "output" then print("T:", tostring(rec.expression)) end
end
