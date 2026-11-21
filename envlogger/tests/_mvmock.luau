local Sandbox = require("../src/core/sandbox")
local r = Sandbox.run([[
-- MoonVeil shim prototype: safeenv_roblox reads env + genv and touches Parent
local env = getfenv()
local genv = getfenv()
local function boot(...)
	local args = {...}
	-- typical safeenv: resolve script via env, then walk parents
	local scriptRef = env.script
	local parent = scriptRef and scriptRef.Parent
	print("boot parent:", parent)
	-- also: instances created through a proxy table
	local w = env.Instance.new("WorldModel")
	print("w:", w)
	local svc = env.game:GetService("ReplicatedStorage")
	-- MoonVeil safeenv caches the service INSIDE a register table then reads .Parent
	local reg = {}
	reg.svc = svc
	print("reg.svc.Parent:", reg.svc.Parent)
	return parent
end
boot(1, 2, 3)
]], { timeout = 20, maxExplored = 0 })
for _, e in ipairs(r.outputs or {}) do print(">", e.text) end
print("err:", r.err)
