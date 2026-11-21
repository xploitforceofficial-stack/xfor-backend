local Sandbox = require("../src/core/sandbox")

local src = [==[
local e = getfenv()
print("type(pcall):", type(e.pcall))
local ok, v = pcall(function() return e.pcall end)
local t = type(v)
print("materialized pcall type:", t)
local okIdx, r = pcall(function() return e.pcall.FindFirstChild end)
print("pcall.FindFirstChild after getfenv:", okIdx)
local mt = getmetatable(e.pcall)
print("pcall has metatable:", mt ~= nil)
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
