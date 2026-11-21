local Sandbox = require("../src/core/sandbox")
local src = [==[
local results = {}
local n = nil
local ok1, e1 = pcall(function() n:SetControlPoints({}) end)
results[#results+1] = "nilSet=" .. tostring(ok1) .. "/" .. tostring(e1)
local ok2, e2 = pcall(function() return n.Position end)
results[#results+1] = "nilPos=" .. tostring(ok2) .. "/" .. tostring(e2)
local p = Instance.new("Path2D")
local ok3, e3 = pcall(function() p:SetControlPoints({}) end)
results[#results+1] = "realSet=" .. tostring(ok3) .. "/" .. tostring(e3)
print(table.concat(results, "\n"))
]==]
local r = Sandbox.run(src, { timeout = 15, softInstanceCall = true })
print("err", tostring(r.err))
for _, rec in ipairs(r.trace.records) do
  if rec.kind == "note" and tostring(rec.expression):find("safeIndex") then print("NOTE", rec.expression) end
  if rec.kind == "output" then print("OUT", tostring(rec.expression)) end
end
