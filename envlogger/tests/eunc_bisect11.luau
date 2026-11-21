local lfs = require("@lune/fs")
local Sandbox = require("../src/core/sandbox")

local src = [=[
local function helper(x) return x end
local unused = helper(1)
do
    local fn = loadstring("return foo")
    local env = { foo = 123 }
    setfenv(fn, env)
    print("[P] call:", tostring(select(1, pcall(fn))), tostring(select(2, pcall(fn))))
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
