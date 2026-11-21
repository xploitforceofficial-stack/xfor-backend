local Sandbox = require("../src/core/sandbox")

local src = [==[
local out = {}
local function try(name, fn)
  local ok, a, b = pcall(fn)
  out[#out+1] = name .. ": ok=" .. tostring(ok) .. " a=" .. tostring(a):sub(1,100) .. " b=" .. tostring(b):sub(1,60)
end

try("typeof game", function() return typeof(game) end)
try("typeof workspace", function() return typeof(workspace) end)
try("typeof script", function() return typeof(script) end)
try("typeof Instance.new", function() return typeof(Instance.new("Part")) end)
try("game type", function() return type(game) end)
try("game+1", function() return game + 1 end)
try("workspace+1", function() return workspace + 1 end)
try("script+1", function() return script + 1 end)
try("part+1", function() return Instance.new("Part") + 1 end)
try("Players", function() return game:GetService("Players") end)
try("LocalPlayer", function() return game:GetService("Players").LocalPlayer end)
try("Character", function() return game:GetService("Players").LocalPlayer.Character end)
try("HRP", function() local c = game:GetService("Players").LocalPlayer.Character return c and c:FindFirstChild("HumanoidRootPart") end)
try("HRP.Position", function() local c = game:GetService("Players").LocalPlayer.Character return c.HumanoidRootPart.Position end)
try("typeof HRP.Position", function() local c = game:GetService("Players").LocalPlayer.Character return typeof(c.HumanoidRootPart.Position) end)
try("workspace.CurrentCamera", function() return workspace.CurrentCamera end)
try("camera.CFrame", function() return workspace.CurrentCamera.CFrame end)
try("camera.CFrame.Position", function() return workspace.CurrentCamera.CFrame.Position end)
try("Part.Position", function() local p = Instance.new("Part") return p.Position end)
try("typeof Part.Position", function() local p = Instance.new("Part") return typeof(p.Position) end)
try("Part.Position+vec", function() local p = Instance.new("Part") return p.Position + Vector3.new(1,2,3) end)
try("Path2D instance", function() local g = Instance.new("Path2D") return g end)
try("Path2D.SetControlPoints", function() local g = Instance.new("Path2D") return g.SetControlPoints end)
try("Path2D:SetControlPoints call", function() local g = Instance.new("Path2D") return g:SetControlPoints({}) end)
try("FindFirstOfClass camera", function() return workspace:FindFirstChildOfClass("Camera") end)
try("typeof workspace camera", function() return typeof(workspace.CurrentCamera) end)
try("camera + 1", function() return workspace.CurrentCamera + 1 end)
try("enum", function() return Enum.PartType.Block end)
try("typeof enum", function() return typeof(Enum.PartType.Block) end)
try("Vector3 arith", function() return Vector3.new(1,0,0) + Vector3.new(0,1,0) end)
try("typeof Vector3", function() return typeof(Vector3.new()) end)
try("CFrame.Position type", function() return typeof(CFrame.new().Position) end)

for i=1,#out do print(out[i]) end
print("TOTAL " .. #out)
]==]

local r = Sandbox.run(src, { timeout = 15, allowHttp = false, maxExplored = 0 })
print("err", tostring(r.err))
for _, o in ipairs(r.outputs or {}) do print("OUT:", tostring(o)) end
for _, rec in ipairs(r.trace.records) do
  if rec.kind == "output" then print("T:", tostring(rec.expression)) end
  if rec.kind == "note" then print("N:", tostring(rec.expression):sub(1,200)) end
end
