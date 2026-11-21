local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local Beautifier = require("../src/analysis/beautifier")

local passed, failed = 0, 0
local failures: { string } = {}

local function check(name: string, condition: boolean, detail: string?)
	if condition then
		passed += 1
	else
		failed += 1
		failures[#failures + 1] = name .. (if detail then "  -> " .. detail else "")
	end
end

local function loads(text: string): boolean
	local ok = pcall(function()
		return luau.load(text, { environment = {}, injectGlobals = false })
	end)
	return ok
end

local function countLines(s: string): number
	return select(2, string.gsub(s, "\n", "\n"))
end
local function roundTrips(name: string, source: string)
	local out = Beautifier.format(source)
	check(name .. " loads", loads(out), string.sub(out, 1, 200))
	check(name .. " line count preserved", countLines(out) == countLines(source),
		"input " .. countLines(source) .. " vs output " .. countLines(out))
	return out
end

for _, path in ipairs({
	"Samples/moonsecv3sample.lua",
	"Samples/prometheusORwearedevs.lua",
	"Samples/prometheusORwearedevsLUAU.lua",
}) do
	local ok, source = pcall(fs.readFile, path)
	if not ok then
		check("read " .. path, false, "missing")
	else
		local out = roundTrips(path, source)

		if string.find(path, "moonsec", 1) then
			check(path .. " keeps banner", string.find(out, "This file was protected with MoonSec V3", 1, true) ~= nil)
		end
	end
end

do
	local source = [=[
local Players = game:GetService("Players")
local player = Players.LocalPlayer

local function greet(name)
	print("hello " .. name)
end

player.CharacterAdded:Connect(function(character)
	local humanoid = character:WaitForChild("Humanoid")
	humanoid.Died:Connect(function()
		warn("died")
	end)
end)

local config = {
	enabled = true,
	items = { "a", "b", "c" },
}
]=]
	local out = Beautifier.format(source)
	check("idiomatic loads", loads(out))
	check("idiomatic keeps connect", string.find(out, "CharacterAdded:Connect(", 1, true) ~= nil)
	check("idiomatic has no double space", string.find(out, "  ", 1, true) == nil, out)
	check("idiomatic indents body", string.find(out, "\n\tprint(", 1, true) ~= nil, out)
end

do

	local out = Beautifier.format("local x=1 local y=2 print(x+y)")
	check("minified one-liner stays one line", out == "local x = 1 local y = 2 print(x + y)", out)

	local out = Beautifier.format("x = 1 - -2")
	check("minus minus stays safe", loads(out) and string.find(out, "--", 1, true) == nil, out)

	local out = Beautifier.format("local t={} t[1]=5")
	check("indexing hugs", loads(out) and string.find(out, "t [1]", 1, true) == nil, out)

	local out = Beautifier.format("obj:Method(1, 2)")
	check("method form kept", string.find(out, "obj:Method(1, 2)", 1, true) ~= nil, out)

	local out = Beautifier.format("local f = function() return 1 end")
	check("short function inline", string.find(out, "function() return 1 end", 1, true) ~= nil, out)

	local out = Beautifier.format("local x = 1 -- counter")
	check("comment survives", string.find(out, "-- counter", 1, true) ~= nil, out)
	check("comment stays on line", string.find(out, "1 -- counter", 1, true) ~= nil, out)

	local out = Beautifier.format("if a then b() end")
	check("statement if stays one line", out == "if a then b() end", out)

	local out = Beautifier.format("if a then\nb()\nend")
	check("multi-line if body indents", out == "if a then\n\tb()\nend", out)

	local source = 'local s = [[line1\nline2\n]]\nreturn s'
	local out = Beautifier.format(source)
	check("long string survives", string.find(out, "[[line1\nline2\n]]", 1, true) ~= nil, out)
	check("long string loads", loads(out))
end

do

	local out = Beautifier.format("local x = if a then b else c")
	check("if-expression inline", string.find(out, "local x = if a then b else c", 1, true) ~= nil, out)
	check("if-expression loads", loads(out))

	local out = Beautifier.format("local x = if a then b else c end")
	check("if-expression keeps end", string.find(out, "if a then b else c end", 1, true) ~= nil, out)

	local out = Beautifier.format("if a then b() end")
	check("statement if stays one line", out == "if a then b() end", out)

	local out = Beautifier.format("if a then\nb()\nend")
	check("statement if multi-line body indents", out == "if a then\n\tb()\nend", out)
end

do

	local out = Beautifier.format("repeat x = x + 1 until x > 10")
	check("repeat one-liner preserved", out == "repeat x = x + 1 until x > 10", out)
	check("repeat loads", loads(out))

	local out = Beautifier.format("repeat\nx = x + 1\nuntil x > 10")
	check("repeat body indents", out == "repeat\n\tx = x + 1\nuntil x > 10", out)
end

print(string.format("\nbeautifier: %d passed, %d failed", passed, failed))
if failed > 0 then
	for _, line in ipairs(failures) do
		print("  FAIL  " .. line)
	end
	process.exit(1)
end
