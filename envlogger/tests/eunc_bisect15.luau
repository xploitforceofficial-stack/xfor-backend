local Sandbox = require("../src/core/sandbox")

local src = [[
do
    local f2 = loadstring("return bar()")
    setfenv(f2, { bar = function() return 2 end })
    print("[P] callglobal:", tostring(f2()))
    local f3 = loadstring("return foo + foo")
    setfenv(f3, { foo = 3 })
    print("[P] arith:", tostring(f3()))
end
]]

local ok, res = pcall(Sandbox.run, src, { timeout = 30, maxNest = 1, name = "probe" })
print("ok:", tostring(ok), type(res) == "table" and (tostring(res.ok) .. " err=" .. tostring(res.err):sub(1,80)) or "")
if type(res) == "table" then
	for _, item in (res.outputs or {}) do
		local t = if type(item) == "table" then tostring(item.text or item[1]) else tostring(item)
		print("out:", t)
	end
end
