local lfs = require("@lune/fs")
local Sandbox = require("../src/core/sandbox")

local src = [=[
do
    -- first loadstring of this source: cache miss, real path
    local fn = loadstring("return foo")
    setfenv(fn, { foo = 123 })
    print("[P1] first:", tostring(select(1, pcall(fn))), tostring(select(2, pcall(fn))))
    -- second loadstring of the SAME source: duplicate path
    local fn2 = loadstring("return foo")
    setfenv(fn2, { foo = 456 })
    print("[P2] second:", tostring(select(1, pcall(fn2))), tostring(select(2, pcall(fn2))))
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
