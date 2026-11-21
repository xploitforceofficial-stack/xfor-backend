local Sandbox = require("../src/core/sandbox")

local src = [[
print("[P] has LOCAL hook:", type(__FUHD_LOCAL__))
print("[P] has OP hook:", type(__FUHD_OP__))
local a = loadstring("print('[inner] type foo:', type(foo)); return foo")
setfenv(a, { foo = 1, print = print })
local ra = a()
print("[P] got:", tostring(ra))
]]

local ok, res = pcall(Sandbox.run, src, { timeout = 30, maxNest = 1, name = "probe" })
print("ok:", tostring(ok), type(res) == "table" and tostring(res.ok) or "")
if type(res) == "table" then
	for _, item in (res.outputs or {}) do
		local t = if type(item) == "table" then tostring(item.text or item[1]) else tostring(item)
		print("out:", t)
	end
end
