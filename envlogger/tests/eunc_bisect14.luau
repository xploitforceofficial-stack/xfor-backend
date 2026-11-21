local Sandbox = require("../src/core/sandbox")

local src = [[
do
    local fn = loadstring("return 42")
    print("[P] const:", tostring(fn()))
    local fn2 = loadstring("local x = 5\nreturn x")
    print("[P] local:", tostring(fn2()))
    local fn3 = loadstring("return foo")
    setfenv(fn3, { foo = 123 })
    print("[P] envfoo:", tostring(fn3()))
end
]]

local ok, res = pcall(Sandbox.run, src, { timeout = 30, maxNest = 1, name = "probe" })
print("ok:", tostring(ok), type(res) == "table" and tostring(res.ok) or "")
if type(res) == "table" then
	for _, item in (res.outputs or {}) do
		local t = if type(item) == "table" then tostring(item.text or item[1]) else tostring(item)
		print("out:", t)
	end
end
