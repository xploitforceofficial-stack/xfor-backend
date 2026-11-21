local fs = require("@lune/fs")
local Sandbox = require("../src/core/sandbox")

local source = fs.readFile("Samples/eunc.lua")

source ..= [[

-- appended: post-battery check of the two persistently failing bodies
do
    local function report(label, ok, extra)
        print("[POST] " .. label .. ": " .. tostring(ok) .. (extra and (" | " .. extra) or ""))
    end
    -- setfenv test
    local ok1, e1 = pcall(function()
        local fn = loadstring("return foo")
        local env = { foo = 123 }
        setfenv(fn, env)
        assert(fn() == 123)
    end)
    report("setfenv-ls", ok1, e1)
    -- nan test
    local ok2, e2 = pcall(function()
        assert(type(utf8.graphemes) == "function")
        assert(math.isnan == nil or type(math.isnan) == "function" or math.isnan(0 / 0))
        local nan = 0 / 0
        assert(nan ~= nan)
    end)
    report("nan-block", ok2, e2)
end
]]

local ok, res = pcall(Sandbox.run, source, { timeout = 90, maxNest = 1, name = "eunc.lua" })
print("run ok:", tostring(ok))
if type(res) == "table" then
	for _, item in (res.outputs or {}) do
		local t = if type(item) == "table" then tostring(item.text or item[1]) else tostring(item)
		if t:find("%[POST%]") or t:find("Score") then
			print(t)
		end
	end
end
