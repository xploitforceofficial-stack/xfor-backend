local Sandbox = require("../src/core/sandbox")

local r = Sandbox.run([[
local chunk = loadstring("return game:GetService('ReplicatedStorage')")
local svc = chunk()
print("svc:", svc)
print("svc.Parent:", svc.Parent)
-- via setfenv'd chunk with custom env missing game:
local fn = loadstring("return game")
local ok, res = pcall(function()
	setfenv(fn, { game = nil })
	return fn()
end)
print("nil-game env:", ok, res)
-- what the VM does: getfenv() then index unknown global
local g = getfenv()
print("unknown global:", g.ThisDoesNotExistAnywhere)
print("then .Parent:", g.ThisDoesNotExistAnywhere and g.ThisDoesNotExistAnywhere.Parent)
]], { timeout = 20, maxExplored = 0 })
for _, e in ipairs(r.outputs or {}) do print(">", e.text) end
print("err:", r.err)
