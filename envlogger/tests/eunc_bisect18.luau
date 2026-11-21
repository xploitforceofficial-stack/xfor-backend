local Sandbox = require("../src/core/sandbox")

local src = [[
local a = loadstring("return foo")
setfenv(a, { foo = 1 })
local ra = a()
print("[P] a direct:", tostring(ra), type(ra))
]]

local ok, res = pcall(Sandbox.run, src, { timeout = 30, maxNest = 1, name = "probe" })
print("ok:", tostring(ok), type(res) == "table" and tostring(res.ok) or "")
if type(res) == "table" then
	for _, item in (res.outputs or {}) do
		local t = if type(item) == "table" then tostring(item.text or item[1]) else tostring(item)
		print("out:", t)
	end
end
