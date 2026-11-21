local Sandbox = require("../src/core/sandbox")

local src = [[
local a = 0/0
local b = (a ~= a)
print("neq:", tostring(b))
local c = 0/0
print("selfneq:", tostring(c ~= c))
]]
local ok, res = pcall(Sandbox.run, src, { timeout = 30, maxNest = 1, name = "probe" })
print("ok:", tostring(ok))
if type(res) == "table" then
	for _, item in (res.outputs or {}) do
		local t = if type(item) == "table" then tostring(item.text or item[1]) else tostring(item)
		print("out:", t)
	end
	print("err:", tostring(res.err):sub(1, 120))
end
