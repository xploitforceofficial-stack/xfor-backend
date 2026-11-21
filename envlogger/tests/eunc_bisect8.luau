local lfs = require("@lune/fs")
local Sandbox = require("../src/core/sandbox")

local src = lfs.readFile("Samples/eunc.lua")
src ..= "\n" .. [=[
do
    local fn = loadstring("return foo")
    local okS, s = pcall(debug.info, fn, "s")
    print("[POST6] debug.info src:", tostring(okS), tostring(s))
    local env = { foo = 123 }
    local ret = setfenv(fn, env)
    print("[POST6] same fn:", tostring(ret == fn))
    local okc, c = pcall(fn)
    print("[POST6] call ok:", tostring(okc), "val:", tostring(c))
    local okg, g = pcall(getfenv, fn)
    if okg then
        print("[POST6] getfenv(fn).foo:", tostring(g.foo))
    else
        print("[POST6] getfenv(fn) err:", tostring(g))
    end
end
]=]

local ok, res = pcall(Sandbox.run, src, { timeout = 90, maxNest = 1, name = "eunc.lua" })
print("run ok:", tostring(ok), type(res) == "table" and ("res.ok=" .. tostring(res.ok)) or "")
if type(res) == "table" then
	for _, item in (res.outputs or {}) do
		local t = if type(item) == "table" then tostring(item.text or item[1]) else tostring(item)
		if t:find("%[POST6%]") then
			print(t)
		end
	end
end
