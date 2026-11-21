local lfs = require("@lune/fs")
local Sandbox = require("../src/core/sandbox")

local src = [=[
do
    local fn = loadstring("return foo")
    local okS, s = pcall(debug.info, fn, "s")
    print("[P] debug.info src:", tostring(okS), tostring(s))
    local env = { foo = 123 }
    setfenv(fn, env)
    local okc, c = pcall(fn)
    print("[P] call ok:", tostring(okc), "val:", tostring(c))
end
]=]

local ok, res = pcall(Sandbox.run, src, { timeout = 30, maxNest = 1, name = "probe" })
print("ok:", tostring(ok), type(res) == "table" and tostring(res.ok) or "")
if type(res) == "table" then
	for _, item in (res.outputs or {}) do
		local t = if type(item) == "table" then tostring(item.text or item[1]) else tostring(item)
		print("out:", t)
	end
end
