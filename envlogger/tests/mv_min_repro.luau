local Sandbox = require("../src/core/sandbox")

local src = [==[
local e = getfenv()
local cg = e.game:GetService("CoreGui")

local f1 = e.pcall
local ok1 = pcall(function() return (f1 or cg).FindFirstChild end)
print("1 local-held pcall:", ok1)

local function holder() return e.ipairs end
local f2 = holder()
local ok2 = pcall(function() return (f2 or cg).FindFirstChild end)
print("2 func-returned ipairs:", ok2)

local ok3 = pcall(function() return (e.checkcaller or cg).FindFirstChild end)
print("3 checkcaller:", ok3)

local ok4 = pcall(function() return (e.gethui() or cg).FindFirstChild end)
print("4 gethui():", ok4)

local box = { fn = e.select }
local ok5 = pcall(function() return (box.fn or cg).FindFirstChild end)
print("5 boxed select:", ok5)

local ok6 = pcall(function() return (rawget(e, "type") or cg).FindFirstChild end)
print("6 rawget type:", ok6)
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
