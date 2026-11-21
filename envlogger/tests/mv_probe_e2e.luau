local Sandbox = require("../src/core/sandbox")

local src = [==[
local e = getfenv()
local _p = e.pcall
local _h = e.gethui
local _g = e.game
local _cg = _g:GetService("CoreGui")
local _i = e.ipairs

local okA = pcall(function() return (_p or _cg).FindFirstChild end)
print("pcall.FindFirstChild:", okA)
local okB = pcall(function() return (_i or _cg).FindFirstChild end)
print("ipairs.FindFirstChild:", okB)
local okC = pcall(function() return (e.getfenv or _cg).FindFirstChild end)
print("getfenv.FindFirstChild:", okC)
local okD = pcall(function() return (e.game or _cg).FindFirstChild end)
print("game.FindFirstChild:", okD)
local okE = pcall(function() return _cg.FindFirstChild(_cg, "x") end)
print("cg direct:", okE)
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
