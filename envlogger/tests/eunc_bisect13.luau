local Sandbox = require("../src/core/sandbox")

local src = [[
do
    local fn = loadstring("return foo")
    setfenv(fn, { foo = 123 })
    local r = fn()
    print("[P] raw result:", tostring(r), type(r))
    -- now with a comparison, like assert(fn() == 123)
    print("[P] cmp:", tostring(r == 123))
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
