local luau = require("@lune/luau")
local process = require("@lune/process")

local Instrument = require("../src/core/instrument")
local Sandbox = require("../src/core/sandbox")
local Static = require("../src/analysis/static")

local passed = 0
local failed = 0
local failures: { string } = {}

local function check(label: string, ok: boolean, detail: string?)
	if ok then
		passed += 1
	else
		failed += 1
		failures[#failures + 1] = label .. (detail and (" (" .. detail .. ")") or "")
	end
end

do

	local src = "local x = 0\nwhile x < 3 do x = x + 1 end\nreturn x"
	local rewritten = Instrument.apply(src)
	check("tight loop rewritten", rewritten ~= nil)
	if rewritten then
		check("check spliced into body", string.find(rewritten, "__FUHD_CHECK__();x = x + 1 end", 1, true) ~= nil
			and string.find(rewritten, "__FUHD_OP__", 1, true) ~= nil)
		local globals = setmetatable({}, { __index = _G })
		globals.__FUHD_CHECK__ = function() end
		globals.__FUHD_OP__ = function(op, a, b)
			if op == "eq" then return a == b elseif op == "ne" then return a ~= b elseif op == "lt" then return a < b elseif op == "le" then return a <= b elseif op == "gt" then return a > b elseif op == "ge" then return a >= b end return false
		end
		globals.__FUHD_LOCAL__ = function(_name, value)
			return value
		end
		local fn = luau.load(rewritten, { environment = globals, injectGlobals = true })
		check("rewritten runs", fn() == 3)
	end
end

do

	local src = "local function f(x: number): (number, string)\n\treturn x, 'ok'\nend\nreturn f(1)"
	local rewritten = Instrument.apply(src)
	check("typed fn rewritten", rewritten ~= nil)
	if rewritten then
		local globals = setmetatable({}, { __index = _G })
		globals.__FUHD_CHECK__ = function() end
		globals.__FUHD_OP__ = function(op, a, b)
			if op == "eq" then return a == b elseif op == "ne" then return a ~= b elseif op == "lt" then return a < b elseif op == "le" then return a <= b elseif op == "gt" then return a > b elseif op == "ge" then return a >= b end return false
		end
		globals.__FUHD_LOCAL__ = function(_name, value)
			return value
		end
		local fn = luau.load(rewritten, { environment = globals, injectGlobals = true })
		local a, b = fn()
		check("typed fn runs", a == 1 and b == "ok")
	end
end

do

	local src = 'local s = "while for repeat function"\nfor i = 1, N do s = s end\nreturn s'
	local rewritten = Instrument.apply(src)
	check("string keywords ignored", rewritten ~= nil)
	if rewritten then

		check("splice + local binding", select(2, string.gsub(rewritten, "__FUHD_CHECK__", "")) == 3)
		check("check bound to local", string.find(rewritten, "local __FUHD_CHECK__ = __FUHD_CHECK__;", 1, true) ~= nil, rewritten)

		check("numeric for stride check", string.find(rewritten, "if i % 256 == 0 then __FUHD_CHECK__() end", 1, true) ~= nil, rewritten)
	end
end

do

	local src = 'for i = 1, 8 do for j = 1, 100 do end end\nwhile true do break end'
	local rewritten = Instrument.apply(src)
	check("constant loops rewritten", rewritten ~= nil)
	if rewritten then

		check("constant for skipped", select(2, string.gsub(rewritten, "__FUHD_CHECK__", "")) == 3, rewritten)
		check("while still checked", string.find(rewritten, "while true do __FUHD_CHECK__();", 1, true) ~= nil, rewritten)
	end
end

do

	local okApply = pcall(Instrument.apply, "local x = 'unterminated\nwhile true do end")
	check("malformed input safe", okApply)
end

do

	local bytes = string.char(0x01, 0x02, 0x03) .. "not source"
	check("bytecode skipped", Instrument.apply(bytes) == nil)
end

do

	local src = "local t = {}\nfunction t:method(a) return a + 1 end\nreturn t:method(1)"
	local rewritten = Instrument.apply(src)
	check("method fn rewritten", rewritten ~= nil)
	if rewritten then
		local globals = setmetatable({}, { __index = _G })
		globals.__FUHD_CHECK__ = function() end
		globals.__FUHD_OP__ = function(op, a, b)
			if op == "eq" then return a == b elseif op == "ne" then return a ~= b elseif op == "lt" then return a < b elseif op == "le" then return a <= b elseif op == "gt" then return a > b elseif op == "ge" then return a >= b end return false
		end
		globals.__FUHD_LOCAL__ = function(_name, value)
			return value
		end
		local fn = luau.load(rewritten, { environment = globals, injectGlobals = true })
		check("method fn runs", fn() == 2)
	end
end

do

	local rewritten = Instrument.apply("local x = 5\nprint(x)")
	check("scalar local wrapped", rewritten ~= nil)
	if rewritten then
		check("wrap intact", string.find(rewritten, 'local x = __FUHD_LOCAL__("x", 5)', 1, true) ~= nil, rewritten)

		check("no byte eaten", string.find(rewritten, "%f[%a]rint%(") == nil, rewritten)
	end

	rewritten = Instrument.apply("local a, b = 1, 2\nprint(a, b)")
	check("multi-assign untouched", rewritten == nil or string.find(rewritten, "__FUHD_LOCAL__", 1, true) == nil, tostring(rewritten))

	rewritten = Instrument.apply("local f = function() return 1 end\nprint(f())")
	check("fn local tracked", rewritten ~= nil and string.find(rewritten, "__FUHD_LOCAL__", 1, true) ~= nil, tostring(rewritten))
	if rewritten then
		check("fn body still checked", string.find(rewritten, "__FUHD_CHECK__", 1, true) ~= nil, rewritten)
	end

	rewritten = Instrument.apply("local x = -5\nprint(x)")
	check("unary init wrapped", rewritten ~= nil and string.find(rewritten, '__FUHD_LOCAL__("x", -5)', 1, true) ~= nil, tostring(rewritten))

	rewritten = Instrument.apply("if game then print(1) else print(2) end")
	check("branch cond wrapped", rewritten ~= nil
		and string.find(rewritten, "__FUHD_BRANCH__(1, \"game\", \"if\", game, 1)", 1, true) ~= nil, tostring(rewritten))
	check("chain end marker inserted", rewritten ~= nil
		and string.find(rewritten, "__FUHD_BRANCH_END__()", 1, true) ~= nil, tostring(rewritten))
	if rewritten then
		local globals = setmetatable({}, { __index = _G })
		globals.__FUHD_CHECK__ = function() end
		globals.__FUHD_OP__ = function(op, a, b)
			if op == "eq" then return a == b elseif op == "ne" then return a ~= b elseif op == "lt" then return a < b elseif op == "le" then return a <= b elseif op == "gt" then return a > b elseif op == "ge" then return a >= b end return false
		end
		globals.__FUHD_LOCAL__ = function(_name, value)
			return value
		end
		globals.__FUHD_BRANCH__ = function(_id, _text, cond)
			return cond
		end
		globals.__FUHD_BRANCH_END__ = function() end
		globals.__FUHD_ARG__ = function(_name, value)
			return value
		end
		local fn = luau.load(rewritten, { environment = globals, injectGlobals = true })
		local ok, a, b = pcall(fn)
		check("branch rewrite runs", ok and a == nil, tostring(b))
	end

	rewritten = Instrument.apply("if a then x = 1 elseif b then x = 2 end")
	check("elseif cond wrapped", rewritten ~= nil
		and string.find(rewritten, "__FUHD_BRANCH__(1,", 1, true) ~= nil
		and string.find(rewritten, "__FUHD_BRANCH__(2,", 1, true) ~= nil, tostring(rewritten))

	rewritten = Instrument.apply("print(a, 1, a + 1)")
	check("identifier args tagged", rewritten ~= nil
		and string.find(rewritten, 'print(__FUHD_ARG__("a", a), 1, a + 1)', 1, true) ~= nil, tostring(rewritten))
	rewritten = Instrument.apply("print('hi')")
	check("string literal arg untouched", rewritten == nil
		or string.find(rewritten, "__FUHD_ARG__", 1, true) == nil, tostring(rewritten))
end

do

	local t0 = os.clock()
	local result = Sandbox.run("local x = 0\nwhile true do x = x + 1 end", { timeout = 2, maxNest = 4 })
	local elapsed = os.clock() - t0
	check("pure loop cut", result.exhausted == true)
	check("pure loop cut fast", elapsed < 5, string.format("%.1f", elapsed))
end

do

	local result = Sandbox.run("local x = 0\nfor i = 1, math.huge do x = x + 1 end", { timeout = 2, maxNest = 4 })
	check("huge for cut", result.exhausted == true)
end

do

	local t0 = os.clock()
	local result = Sandbox.run("local function f() return f() end\nf()", { timeout = 3, maxNest = 4 })
	local elapsed = os.clock() - t0
	check("recursion terminated", not result.ok, tostring(result.err))
	check("recursion fast", elapsed < 5, string.format("%.1f", elapsed))
end

do

	local result = Sandbox.run("local t = {}\nfor i = 1, 10 do t[i] = i * 2 end\nprint(t[10])", { timeout = 3, maxNest = 4 })
	check("normal runs", result.ok == true)
	check("normal outputs", #result.outputs == 1)
end

do

	local bytecode = luau.compile("print('compiled')\nlocal t = game:GetService('Players')\nprint(t.Name)")
	check("bytecode is binary", string.byte(bytecode, 1) ~= nil and string.byte(bytecode, 1) < 0x20)
	local result = Sandbox.run(bytecode, { timeout = 3, maxNest = 4 })
	check("bytecode runs", result.ok == true, tostring(result.err))
	check("bytecode outputs", #result.outputs == 2)
	local found = false
	for _, output in ipairs(result.outputs) do
		if output.text == "compiled" then
			found = true
		end
	end
	check("bytecode output content", found)

	local sawService = false
	for _, record in ipairs(result.trace.records) do
		if string.find(record.expression, "GetService", 1, true) then
			sawService = true
		end
	end
	check("bytecode trace recovered", sawService)
end

do
	local findings = Static.analyze("-- banner\nlocal x = 'https://example.com/path?q=1'\nprint(x)")
	check("plain url found", #findings.urls == 1 and findings.urls[1] == "https://example.com/path?q=1")
end

do
	local findings = Static.analyze("local w = 'https://discord.com/api/webhooks/123/abc'")
	check("webhook classified", #findings.webhooks == 1 and #findings.urls == 0)
end

do

	local findings = Static.analyze([['\104\116\116\112\115\058\047\047\101\118\105\108\046\099\111\109']])
	check("escaped url decoded", #findings.urls == 1 and findings.urls[1] == "https://evil.com")
end

do
	local findings = Static.analyze("return({RP=bit32.band}):J()(...)")
	check("shell detected", #findings.shells >= 1)
end

do

	local findings = Static.analyze("-- [https://dsc.gg/example]")
	check("bracket stripped", #findings.urls == 1 and findings.urls[1] == "https://dsc.gg/example")
end

do

	local result = Sandbox.run("\239\187\191print('a')", { timeout = 10 })
	check("bom source runs", result.ok == true, tostring(result.err))
end

do

	local result = Sandbox.run("print(\226\128\156h\226\128\157)", { timeout = 10 })
	check("smart quotes recovered", result.ok == true, tostring(result.err))
end

do

	local result = Sandbox.run("local f = loadstring('\\239\\187\\191print(1)') if f then f() end", { timeout = 10 })
	check("bom stage runs", result.ok == true, tostring(result.err))
end

do

	local function lowersTo(src: string): string?
		return Instrument.lowerBitwise(src)
	end
	local function compiles(src: string): boolean
		local ok = pcall(function()
			luau.load(src)
		end)
		return ok
	end
	local function evalExpr(expr: string): any
		local lowered = Instrument.lowerBitwise("return " .. expr) or ("return " .. expr)
		local fn = luau.load("local a, b, c, x, y, i = 5, 3, 6, 2, 200, 4\n" .. lowered)
		return fn()
	end

	check("raw xor fails to compile", not compiles("return a ~ b"))
	local cases = {
		{ expr = "a[1] ~ ((1 * 17 + 31) % 256)" },
		{ expr = "a & b", want = bit32.band(5, 3) },
		{ expr = "a | b", want = bit32.bor(5, 3) },
		{ expr = "x << 3", want = bit32.lshift(2, 3) },
		{ expr = "y >> 5", want = bit32.rshift(200, 5) },
		{ expr = "~a", want = bit32.bnot(5) },
		{ expr = "a ~ b + c", want = bit32.bxor(5, 3 + 6) },
		{ expr = "(x << 3) | (y >> 5)", want = bit32.bor(bit32.lshift(2, 3), bit32.rshift(200, 5)) },
		{ expr = "a ~ b ~ c", want = bit32.bxor(bit32.bxor(5, 3), 6) },
	}
	for _, c in ipairs(cases) do
		local lowered = lowersTo("return " .. c.expr)
		check("lowers " .. c.expr, lowered ~= nil and compiles(lowered), tostring(lowered))
		if c.want ~= nil then
			check("evals " .. c.expr, evalExpr(c.expr) == c.want, tostring(evalExpr(c.expr)))
		end
	end

	check("not-equal untouched", lowersTo("return a ~= b") == nil)

	check("plain source untouched", lowersTo("return a + b") == nil)

	local result = Sandbox.run("local k = 42\nlocal r = (k ~ 7) + (k << 1)\nprint(r)", { timeout = 10 })
	check("bitwise decoder runs in sandbox", result.ok == true, tostring(result.err))
end

print(string.format("\ninstrument: %d passed, %d failed", passed, failed))
if failed > 0 then
	for _, line in ipairs(failures) do
		print("  FAIL  " .. line)
	end
	process.exit(1)
end
