local Sandbox = require("../src/core/sandbox")

local src = [[
do
    local fn = loadstring("print('[P] foo:', tostring(foo)); print('[P] bar:', tostring(bar))")
    setfenv(fn, { foo = 123, bar = nil, print = print })
    print("[P] call:", tostring(pcall(fn)))
    local fn2 = loadstring("return foo")
    setfenv(fn2, { foo = 123 })
    print("[P] fn2:", tostring(select(1, pcall(fn2))), tostring(select(2, pcall(fn2))))
    local fn3 = loadstring("return 1+1")
    setfenv(fn3, { })
    print("[P] fn3:", tostring(select(1, pcall(fn3))), tostring(select(2, pcall(fn3))))
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
