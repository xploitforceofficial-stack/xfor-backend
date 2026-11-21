local Sandbox = require("../src/core/sandbox")

local src = [[
local folder = Instance.new("Folder")
local names = { "WaitForChild", "FindFirstChild", "Clone", "Destroy", "GetChildren", "IsA", "GetFullName" }
for _, n in ipairs(names) do
	local fn = folder[n]
	local ok, s, l, nm, p, v = pcall(debug.info, fn, "slnaf")
	print(n, typeof(fn), tostring(ok), tostring(s), tostring(l), tostring(nm), tostring(p), tostring(v))
end
local parent = workspace
for _, n in ipairs({"WaitForChild", "FindFirstChild"}) do
	local fn = parent[n]
	local ok, s, l, nm = pcall(debug.info, fn, "sln")
	print("workspace." .. n, typeof(fn), tostring(ok), tostring(s), tostring(l), tostring(nm))
end
]]

local ok, res = pcall(Sandbox.run, src, { timeout = 20 })
if not ok then
	print("sandbox error:", res)
	return
end
print("ok:", res.ok, "err:", res.err)
for _, entry in ipairs(res.outputs or {}) do
	print("OUT|" .. tostring(entry.text))
end
