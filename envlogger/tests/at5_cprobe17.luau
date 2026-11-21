local Sandbox = require("../src/core/sandbox")
local Spy = require("../src/core/spy")
local Fidelity = require("../src/env/fidelity")

local src = [[
local folder = Instance.new("Folder")
local names = { "WaitForChild", "FindFirstChild", "Clone", "Destroy", "GetChildren", "IsA", "GetFullName" }
for _, n in ipairs(names) do
	local fn = folder[n]
	if type(fn) == "function" then
		local s, l, nm, p, v = debug.info(fn, "slnaf")
		print(n, s, l, tostring(nm), p, v)
	else
		print(n, "NOT A FUNCTION", typeof(fn))
	end
end
]]

local ok, res = pcall(Sandbox.run, src, { timeout = 20 })
if not ok then
	print("sandbox error:", res)
	return
end
print("ok:", res.ok, "err:", res.err)
for _, line in ipairs(res.output or {}) do
	print("OUT|" .. line)
end
