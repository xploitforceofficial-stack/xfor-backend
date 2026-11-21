local fs = require("@lune/fs")
local Sandbox = require("../src/core/sandbox")

local function run(label: string, code: string)
	local ok, res = pcall(Sandbox.run, code, { timeout = 30, maxNest = 1, name = "probe" })
	if not ok then
		print(label, "SANDBOX CRASH:", tostring(res):sub(1, 150))
		return
	end
	print("==", label, "| ok:", tostring(res.ok), "| err:", tostring(res.err):sub(1, 150))
	if type(res.outputs) == "table" then
		for _, item in res.outputs do
			local t = if type(item) == "table" then tostring(item.text or item[1]) else tostring(item)
			print("   out:", t)
		end
	end
end

run("setfenv-exact", [[
	local fn = loadstring("return foo")
	local env = { foo = 123 }
	setfenv(fn, env)
	print("r1:", fn() == 123)
	local fn2 = loadstring("return bar")
	setfenv(fn2, { bar = "iso" })
	print("r2:", fn2() == "iso")
	print("r3:", bar == nil)
	local before = getfenv(1)
	local fn3 = loadstring("return 1")
	setfenv(fn3, { leaked = true })
	fn3()
	print("r4:", getfenv(1) == before)
	print("r5:", rawget(before, "leaked") == nil)
	print("r6:", type(getfenv(0)) == "table")
	print("r7:", getfenv(0) == getfenv(0))
	print("r8:", type(getfenv(1)) == "table")
]])

run("nan-exact", [[
	print("a:", type(utf8.graphemes) == "function")
	print("b:", math.isnan == nil or type(math.isnan) == "function" or math.isnan(0/0))
	local nan = 0/0
	print("c:", nan ~= nan)
]])
