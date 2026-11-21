local fs = require("@lune/fs")
local Sandbox = require("../src/core/sandbox")

local result = Sandbox.run([=[
	math.randomseed(177465824)
	local a = math.random()
	local i2 = math.random(189, 1164)
	local b = math.random()
	local c = math.random()
	print(string.format("a=%.17g int=%d b=%.17g c=%.17g", a, i2, b, c))
	print("expect: a=0.9598971928030796 int=889 b=0.027539190730015265 c=0.3377740061710911")

	-- error-path checks
	local ok1, e1 = pcall(math.random, 0)
	print("rand(0):", ok1, tostring(e1))
	local ok2, e2 = pcall(math.random, 5, 2)
	print("rand(5,2):", ok2, tostring(e2))
	local ok3, e3 = pcall(math.random, 1, 2, 3)
	print("rand(1,2,3):", ok3, tostring(e3))
	local ok4, e4 = pcall(math.randomseed, "x")
	print("seed('x'):", ok4, tostring(e4))
	-- one-arg form
	local one = math.random(6)
	print("rand(6) in [1,6]:", one >= 1 and one <= 6 and math.floor(one) == one)
]=], { timeout = 30 })

for _, o in ipairs(result.outputs or {}) do
	print(o.text:gsub("\n$", ""))
end
print("sandbox err:", result.err)
