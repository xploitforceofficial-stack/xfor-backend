local lfs = require("@lune/fs")
local Sandbox = require("../src/core/sandbox")

local src = lfs.readFile("Samples/eunc.lua")
src ..= "\n" .. [=[
do
    local fn = loadstring("return foo")
    print("[POST5] src:", debug.info(fn, "s"))
    local env = { foo = 123 }
    local ret = setfenv(fn, env)
    print("[POST5] same fn:", ret == fn)
    print("[POST5] call:", tostring(select(1, pcall(fn))))
    local okg, g = pcall(getfenv, fn)
    print("[POST5] getfenv(fn) ok:", tostring(okg), "foo:", tostring(okg and g.foo))
end
]=]

local ok, res = pcall(Sandbox.run, src, { timeout = 90, maxNest = 1, name = "eunc.lua" })
print("run ok:", tostring(ok))
if type(res) == "table" then
	print("res.ok:", tostring(res.ok), "err:", tostring(res.err):sub(1, 120))
	for _, item in (res.outputs or {}) do
		local t = if type(item) == "table" then tostring(item.text or item[1]) else tostring(item)
		if t:find("%[POST5%]") or t:find("Score") then
			print(t)
		end
	end
else
	print("res:", tostring(res):sub(1, 200))
end
