local Sandbox = require("../src/core/sandbox")

local src = [==[
local e = getfenv()
local gui = e.game:GetService("CoreGui")

local a = (e.gethui or gui)
print("A:", type(a))
local okB, rB = pcall(function() return a.FindFirstChild end)
print("B index dual:", okB, type(rB))

local okC, rC = pcall(function() return gui.FindFirstChild(gui, "x") end)
print("C coregui ffc:", okC, tostring(rC))

local okD = pcall(function()
  for _, child in ipairs(gui:GetChildren()) do
    if child.FindFirstChild then return child:FindFirstChild("x") end
  end
  return "none"
end)
print("D children loop:", okD)

local okE, rE = pcall(function() return e.gethui() end)
print("E gethui() type:", type(rE))
local okF = pcall(function() return e.gethui():FindFirstChild("x") end)
print("F gethui():ffc:", okF)
]==]

local ok, res = pcall(Sandbox.run, src, { timeout = 20, maxNest = 1 })
if not ok then
	print("sandbox failed:", res)
	return
end
print("script ok:", res.ok, "err:", res.err)
for _, o in ipairs(res.outputs or {}) do
	print(o.channel .. "|", o.text)
end
