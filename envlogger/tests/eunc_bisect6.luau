local lfs = require("@lune/fs")
local Sandbox = require("../src/core/sandbox")

local src = lfs.readFile("Samples/eunc.lua")
src ..= [[

do
    -- fresh: what does debug.info say about a loadstring closure?
    local fn = loadstring("return foo")
    print("[POST4] src:", debug.info(fn, "s"))
    print("[POST4] what:", debug.info(fn, "w"))
    -- is setfenvMap keyed right? indirect: setfenv returns the fn
    local env = { foo = 123 }
    local ret = setfenv(fn, env)
    print("[POST4] setfenv returned same fn:", ret == fn)
    print("[POST4] call:", pcall(fn))
    -- check the actual env swap on the host closure via getfenv(fn)
    local okg, g = pcall(getfenv, fn)
    print("[POST4] getfenv(fn):", tostring(okg), tostring(g and g.foo))
end
]]

local ok, res = pcall(Sandbox.run, src, { timeout = 90, maxNest = 1, name = "eunc.lua" })
print("run ok:", tostring(ok))
if type(res) == "table" then
	for _, item in (res.outputs or {}) do
		local t = if type(item) == "table" then tostring(item.text or item[1]) else tostring(item)
		if t:find("%[POST4%]") then
			print(t)
		end
	end
end
