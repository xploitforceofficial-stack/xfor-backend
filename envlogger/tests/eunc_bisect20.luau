local Sandbox = require("../src/core/sandbox")

local src = [[
local a = loadstring("return debug and 1 or 2")
print("[P] debuginfo src:", tostring(pcall(function() return debug == nil end)))
local b = loadstring("return foo")
setfenv(b, { foo = 9, debug = debug })
print("[P] b:", tostring(b()))
]]

local ok, res = pcall(Sandbox.run, src, { timeout = 30, maxNest = 1, name = "probe" })
print("ok:", tostring(ok), type(res) == "table" and tostring(res.ok) or "")
if type(res) == "table" then
	for _, item in (res.outputs or {}) do
		local t = if type(item) == "table" then tostring(item.text or item[1]) else tostring(item)
		print("out:", t)
	end
end
