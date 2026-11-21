local fs = require("@lune/fs")
local Sandbox = require("../src/core/sandbox")

local source = fs.readFile("Samples/eunc.lua")
source ..= [[

do
    -- nan probe: which statement writes a NaN table index?
    local ok, err = pcall(function()
        local nan = 0 / 0
        local t = {}
        t[nan] = 1
    end)
    print("[POST2] nan-index:", tostring(ok), tostring(err))
    -- setfenv probe stepwise
    local ok1, e1 = pcall(function()
        local fn = loadstring("return foo")
        local env = { foo = 123 }
        setfenv(fn, env)
        local r = fn()
        print("[POST2] fn() ->", tostring(r))
        assert(r == 123)
    end)
    print("[POST2] setfenv-ls:", tostring(ok1), tostring(e1))
end
]]

local ok, res = pcall(Sandbox.run, source, { timeout = 90, maxNest = 1, name = "eunc.lua" })
print("run ok:", tostring(ok))
if type(res) == "table" then
	for _, item in (res.outputs or {}) do
		local t = if type(item) == "table" then tostring(item.text or item[1]) else tostring(item)
		if t:find("%[POST2%]") then
			print(t)
		end
	end
end
