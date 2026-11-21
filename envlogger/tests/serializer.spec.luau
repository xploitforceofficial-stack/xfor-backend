local luau = require("@lune/luau")
local process = require("@lune/process")
local Serializer = require("../src/core/serializer")
local Symbol = require("../src/core/symbol")

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

local function roundTrip(name: string, value: any)
	local text = Serializer.value(value)
	local fn = luau.load("return " .. text, { environment = {}, injectGlobals = false })
	local ok, result = pcall(fn)
	if not ok then
		check(name, false, "did not parse: " .. tostring(result) .. "  src=" .. text)
		return
	end

	local function deepEqual(a: any, b: any): boolean
		if a == b then
			return true
		end
		if type(a) ~= "table" or type(b) ~= "table" then
			return false
		end
		for k, v in pairs(a) do
			if not deepEqual(v, b[k]) then
				return false
			end
		end
		for k in pairs(b) do
			if a[k] == nil then
				return false
			end
		end
		return true
	end

	check(name, deepEqual(value, result), "mismatch, src=" .. text)
end

local function parses(name: string, text: string)
	local ok = pcall(function()
		return luau.load("return " .. text, { environment = {}, injectGlobals = false })
	end)
	check(name, ok, "did not parse: " .. text)
end

roundTrip("nil", nil)
roundTrip("true", true)
roundTrip("false", false)
roundTrip("zero", 0)
roundTrip("negative", -42)
roundTrip("float", 3.14159265358979)
roundTrip("tiny float", 1e-300)
roundTrip("huge float", 1.7976931348623157e308)
roundTrip("int-valued float", 2.0)
roundTrip("empty string", "")
roundTrip("plain string", "hello world")

check("nan", Serializer.value(0 / 0) == "0/0")
check("inf", Serializer.value(math.huge) == "math.huge")
check("-inf", Serializer.value(-math.huge) == "-math.huge")
check("integer has no decimal", Serializer.value(1) == "1", Serializer.value(1))

roundTrip("quotes", [[he said "hi"]])
roundTrip("backslash", "back\\slash")
roundTrip("newline", "line1\nline2")
roundTrip("tab", "a\tb")
roundTrip("null byte", "before\0after")
roundTrip("all control bytes", string.char(0, 1, 2, 7, 8, 9, 10, 11, 12, 13, 27, 31, 127))

roundTrip("escape then digit", "\0" .. "5")
roundTrip("escape then digit 2", string.char(1) .. "23")

roundTrip("high bytes", string.char(200, 255, 128, 129))
roundTrip("invalid utf8", "\xff\xfe\xfd")

do
	local all = {}
	for i = 0, 255 do
		all[#all + 1] = string.char(i)
	end
	roundTrip("every byte 0-255", table.concat(all))
end

check("plain ident", Serializer.isIdentifier("foo"))
check("underscore ident", Serializer.isIdentifier("_x1"))
check("reserved rejected", not Serializer.isIdentifier("end"))
check("reserved rejected 2", not Serializer.isIdentifier("nil"))
check("continue rejected", not Serializer.isIdentifier("continue"))
check("leading digit rejected", not Serializer.isIdentifier("1abc"))
check("space rejected", not Serializer.isIdentifier("a b"))
check("empty rejected", not Serializer.isIdentifier(""))

check("index ident", Serializer.index("t", "key") == "t.key")
check("index reserved", Serializer.index("t", "end") == 't["end"]', Serializer.index("t", "end"))
check("index numeric", Serializer.index("t", 3) == "t[3]")

roundTrip("empty table", {})
roundTrip("array", { 1, 2, 3 })
roundTrip("nested array", { 1, { 2, { 3 } } })
roundTrip("string keys", { alpha = 1, beta = 2 })
roundTrip("mixed", { 1, 2, name = "x", [true] = "yes" })
roundTrip("reserved key", { ["end"] = 1, ["function"] = 2 })
roundTrip("numeric key gap", { [1] = "a", [5] = "b" })
roundTrip("negative key", { [-1] = "neg" })
roundTrip("float key", { [1.5] = "half" })
roundTrip("string with quote key", { ['say "hi"'] = 1 })
roundTrip("deep nest", { a = { b = { c = { d = { e = 1 } } } } })

do
	local cyclic: any = { name = "root" }
	cyclic.self = cyclic
	parses("direct cycle", Serializer.value(cyclic))
	check("cycle noted", string.find(Serializer.value(cyclic), "cyclic") ~= nil)
end

do
	local a: any, b: any = {}, {}
	a.other, b.other = b, a
	parses("mutual cycle", Serializer.value(a))
end

do
	local shared = { 1, 2 }
	roundTrip("shared reference", { first = shared, second = shared })
end

do
	local deep: any = {}
	local cursor = deep
	for _ = 1, 50 do
		cursor.next = {}
		cursor = cursor.next
	end
	parses("over-deep table", Serializer.value(deep))
	check("depth limit noted", string.find(Serializer.value(deep), "max depth") ~= nil)
end

do
	local wide = {}
	for i = 1, 1000 do
		wide[i] = i
	end
	local text = Serializer.value(wide, { maxArrayItems = 10 })
	parses("truncated array", text)
	check("array truncation noted", string.find(text, "array entries") ~= nil)
end

do
	local long = string.rep("x", 5000)
	local text = Serializer.value(long, { maxStringBytes = 100 })
	parses("truncated string", text)
	check("string truncation noted", string.find(text, "truncated") ~= nil)
end

do

	local hostile = setmetatable({}, {
		__tostring = function()
			error("gotcha")
		end,
		__index = function()
			error("gotcha")
		end,
	})
	local ok = pcall(Serializer.value, hostile)
	check("hostile metamethods survive", ok)
	if ok then
		parses("hostile output valid", Serializer.value(hostile))
	end
end

do

	local liar = setmetatable({ 1, 2 }, {
		__len = function()
			return 1e6
		end,
	})
	local ok = pcall(Serializer.value, liar, { maxArrayItems = 5 })
	check("lying __len survives", ok)
end

do

	local weird = { [{}] = "table key", [print] = "function key" }
	local ok = pcall(Serializer.value, weird)
	check("exotic keys survive", ok)
	if ok then
		parses("exotic key output valid", Serializer.value(weird))
	end
end

do
	local sample = { zebra = 1, alpha = 2, middle = 3, [1] = "one", [2] = "two" }
	local first = Serializer.value(sample)
	local stable = true
	for _ = 1, 20 do
		if Serializer.value(sample) ~= first then
			stable = false
			break
		end
	end
	check("key order deterministic", stable)
end

check("function -> callable placeholder",
	Serializer.value(print) == "function() end --[[ callback ]]", Serializer.value(print))
parses("function output valid", Serializer.value(print))
parses("thread output valid", Serializer.value(coroutine.create(function() end)))
parses("function in args valid",
	"f(" .. Serializer.arguments({ print, 1 }, 2) .. ")")

do
	local buf = buffer.fromstring("payload\0\255")
	local text = Serializer.value(buf)
	parses("buffer output valid", text)
	check("buffer uses fromstring", string.find(text, "buffer.fromstring") ~= nil, text)
end

do
	local fakeInstance = Symbol.tag({}, {
		kind = "instance",
		expression = 'game:GetService("Players").LocalPlayer',
		typeName = "Instance",
	})
	check(
		"tagged object uses expression",
		Serializer.value(fakeInstance) == 'game:GetService("Players").LocalPlayer'
	)
	check(
		"tagged object nested in table",
		Serializer.value({ target = fakeInstance }, { pretty = false })
			== '{ target = game:GetService("Players").LocalPlayer }'
	)
	check("typeName reported", Symbol.typeName(fakeInstance) == "Instance")
	check("untagged falls back to lua type", Symbol.typeName({}) == "table")
end

check("args basic", Serializer.arguments({ 1, "two", true }, 3) == '1, "two", true')
check("args empty", Serializer.arguments({}, 0) == "")
check("args preserves embedded nil", Serializer.arguments({ nil, 2 }, 2) == "nil, 2", Serializer.arguments({ nil, 2 }, 2))
check("args preserves trailing nil", Serializer.arguments({ 1, nil }, 2) == "1, nil", Serializer.arguments({ 1, nil }, 2))
check("args single line", not string.find(Serializer.arguments({ { a = 1, b = 2 } }, 1), "\n"))

print(string.format("\nserializer: %d passed, %d failed", passed, failed))
if failed > 0 then
	for _, line in ipairs(failures) do
		print("  FAIL  " .. line)
	end
	process.exit(1)
end
