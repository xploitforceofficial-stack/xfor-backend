local Sandbox = require("../src/core/sandbox")
local src = [==[
local results = {}
local p = Instance.new("Path2D")
results[#results+1] = "new=" .. tostring(p ~= nil)
local ok, e = pcall(function() p:SetControlPoints({Vector3.new(0,0,0)}) end)
results[#results+1] = "set=" .. tostring(ok) .. "/" .. tostring(e)
local ok2, cps = pcall(function() return p:GetControlPoints() end)
results[#results+1] = "get=" .. tostring(ok2) .. "/" .. tostring(cps)
-- which classes have SetControlPoints?
for _, cn in ipairs({"Path2D","Frame","Part"}) do
  local o = Instance.new(cn)
  results[#results+1] = cn .. "=" .. tostring(o ~= nil) .. " hasSet=" .. tostring(o.SetControlPoints ~= nil)
end
return table.concat(results, "\n")
]==]
local r = Sandbox.run(src, { timeout = 15, allowHttp = false, maxExplored = 0, softInstanceCall = true })
print("err", tostring(r.err))

for _, rec in ipairs(r.trace.records) do
  if rec.kind == "output" or rec.kind == "return" then print(rec.kind, tostring(rec.expression)) end
end
