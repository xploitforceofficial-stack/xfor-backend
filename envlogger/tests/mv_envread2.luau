local Sandbox = require("../src/core/sandbox")

local src = [==[
local e = getfenv()
print("A idx e.pcall:", type(e.pcall))
print("B direct pcall:", type(pcall))
local ok, r = pcall(function() return 1 end)
print("C pcall call works:", ok, r)
print("D getmetatable(pcall) vs getmetatable(e.pcall):", getmetatable(pcall) ~= nil, getmetatable(e.pcall) ~= nil)
print("E same table?", pcall == e.pcall)
local okF = pcall(function() return (pcall or e.game).FindFirstChild end)
print("F probe direct pcall:", okF)
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
