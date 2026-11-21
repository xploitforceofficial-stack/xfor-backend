local Sandbox = require("../src/core/sandbox")

local src = [[
local a = 0/0
print("a is:", tostring(a))
]]
local ok, res = pcall(Sandbox.run, src, { timeout = 30, maxNest = 1, name = "probe" })
print("run1 ok:", tostring(ok), type(res) == "table" and tostring(res.err):sub(1, 80) or "")
if type(res) == "table" then
	for _, item in (res.outputs or {}) do
		local t = if type(item) == "table" then tostring(item.text or item[1]) else tostring(item)
		print("out:", t)
	end
end
