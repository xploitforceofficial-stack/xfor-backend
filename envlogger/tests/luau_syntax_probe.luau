local Sandbox = require("../src/core/sandbox")

local cases = {
	{ "simple compound", [[
local x = 1
x += 2
print("x", x)
]] },
	{ "indexed compound", [[
local t = { 0, 0 }
local i = 2
t[i] += 3
print("t", t[1], t[2])
]] },
	{ "field compound", [[
local t = { n = 1 }
t.n += 4
print("n", t.n)
]] },
	{ "continue", [[
local s = 0
for i = 1, 5 do
	if i == 3 then continue end
	s = s + i
end
print("s", s)
]] },
	{ "string interp", [[
local who = "roblox"
print(`hi {who} 1+1={1 + 1}`)
]] },
	{ "type annotation", [[
local f = function(n: number): number
	return n * 2
end
print("f", f(21))
]] },
	{ "typed local", [[
local n: string = "yes"
print("typed", n)
]] },
	{ "if expression", [[
local v = if true then 1 else 2
print("ifexpr", v)
]] },
	{ "generalized iteration", [[
local t = { a = 1, b = 2 }
local n = 0
for _, v in t do
	n = n + v
end
print("geniter", n)
]] },
}

for _, case in ipairs(cases) do
	local name, src = case[1], case[2]
	local result = Sandbox.run(src, { timeout = 20, maxExplored = 0 })
	local first = ""
	for _, entry in ipairs(result.outputs or {}) do
		first = tostring(entry.text)
		break
	end
	print(string.format("%-22s ok=%-5s %s %s", name, tostring(result.ok),
		first, result.ok and "" or tostring(result.err):sub(1, 90)))
end
