local Sandbox = require("../src/core/sandbox")

local src = [==[
local e = getfenv()

local function vmInternal()
  local f = e.print  -- captured env fn (now dual => indexable)
  local ok, v = pcall(function() return f.FindFirstChild end)
  return "inner:" .. tostring(ok)
end
print("A:", vmInternal())

local cg = e.game:GetService("CoreGui")
print("B:", type(cg), cg.ClassName)
local ffc = cg.FindFirstChild
print("C:", type(ffc))
local okD = pcall(function() return ffc(cg, "x") end)
print("D ffc(cg):", okD)

local okE = pcall(function() return (ffc or cg).FindFirstChild end)
print("E (ffc or cg).FindFirstChild:", okE)
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
