local fs = require("@lune/fs")
local Sandbox = require("../src/core/sandbox")

local cases = {
	{name = "fresh-loadstring-setfenv-call", code = [[
		local fn = loadstring("return foo")
		local ok = pcall(setfenv, fn, { foo = 123 })
		print("setfenv ok:", ok)
		local okc, res = pcall(fn)
		print("call:", okc, res)
	]]},
	{name = "setfenv-direct", code = [[
		local fn2 = loadstring("return bar")
		setfenv(fn2, { bar = "iso" })
		print("fn2:", fn2())
	]]},
	{name = "getfenv-fn", code = [[
		local fn3 = loadstring("return baz")
		setfenv(fn3, { baz = 9 })
		print("type getfenv(fn3):", type(getfenv(fn3)))
	]]},
	{name = "getfenv-0", code = [[
		print("getfenv(0):", pcall(getfenv, 0))
	]]},
}

for _, case in ipairs(cases) do
	local ok, res = pcall(Sandbox.run, "print('start') " .. case.code, { timeout = 30, maxNest = 1 })
	if not ok then
		print(case.name .. ": SANDBOX CRASH: " .. tostring(res):sub(1, 150))
	else
		local outputs = {}
		if type(res.outputs) == "table" then
			for _, item in res.outputs do
				outputs[#outputs + 1] = if type(item) == "table" then tostring(item.text or item[1]) else tostring(item)
			end
		end
		print(case.name .. ": ok=" .. tostring(res.ok) .. " err=" .. tostring(res.err):sub(1, 120) .. " | " .. table.concat(outputs, " / "))
	end
end
