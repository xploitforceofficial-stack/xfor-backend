local Sandbox = require("../src/core/sandbox")

local source = fs and nil
local lfs = require("@lune/fs")
local src = lfs.readFile("Samples/eunc.lua")
src ..= [[

do
    -- stepwise setfenv post-battery
    local ok0, f0 = pcall(loadstring, "return foo")
    print("[POST3] loadstring ok:", tostring(ok0), type(f0))
    local ok1, e1 = pcall(function()
        local fn = loadstring("return foo")
        local env = { foo = 123 }
        setfenv(fn, env)
        print("[POST3] env set, type fn:", type(fn))
        local r = fn()
        print("[POST3] fn() ->", tostring(r), type(r))
        return r
    end)
    print("[POST3] stepwise:", tostring(ok1), tostring(e1):sub(1, 100))
    -- is getfenv(1) stable?
    local ok2, e2 = pcall(function()
        local before = getfenv(1)
        local fn = loadstring("return 1")
        setfenv(fn, { leaked = true })
        fn()
        print("[POST3] getfenv stable:", getfenv(1) == before)
        print("[POST3] no leak:", rawget(before, "leaked") == nil)
    end)
    print("[POST3] leakcheck:", tostring(ok2), tostring(e2):sub(1, 100))
end
]]

local ok, res = pcall(Sandbox.run, src, { timeout = 90, maxNest = 1, name = "eunc.lua" })
print("run ok:", tostring(ok))
if type(res) == "table" then
	for _, item in (res.outputs or {}) do
		local t = if type(item) == "table" then tostring(item.text or item[1]) else tostring(item)
		if t:find("%[POST3%]") then
			print(t)
		end
	end
end
