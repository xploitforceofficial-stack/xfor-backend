local SrcEdit = require("../src/core/srcedit")
local Instrument = require("../src/core/instrument")

local passed, failed = 0, 0
local failures: { string } = {}

local function check(name: string, condition: boolean, detail: string?)
	if condition then
		passed += 1
	else
		failed += 1
		failures[#failures + 1] = name .. (detail and (" -- " .. detail) or "")
	end
end

local function wrap(src: string): (string?, string?)
	return SrcEdit.wrapFunctions(src, Instrument.tokenize)
end

do
	local out = wrap("local f = function(a) return a end")
	check("flat wrap produces output", out ~= nil)
	check("flat wrap uses __wrapFunc", out ~= nil and string.find(out, "__wrapFunc(", 1, true) ~= nil)
end

do
	local src = "return({f=function(g)return function(x)return g(x)+1 end end,z=function()return 42 end}):f(function(y)return y*2 end)"
	local out, err = wrap(src)
	check("nested wrap produces output", out ~= nil, err)
	if out then
		local fn, cerr = loadstring(out)
		check("nested wrap compiles", fn ~= nil, tostring(cerr))
	end
end

do
	local src = "local a=function() local b=function() local c=function() return 7 end return c() end return b() end return a()"
	local out = wrap(src)
	check("3-level wrap produces output", out ~= nil)
	if out then
		local fn, cerr = loadstring(out)
		check("3-level wrap compiles", fn ~= nil, tostring(cerr))
	end
end

do
	local src = "local function helper(n) return n + 1 end local r = helper(1)"
	local out = wrap(src)
	check("local function rebind", out ~= nil and string.find(out, "helper = __wrapFunc(helper)", 1, true) ~= nil)
end

do
	local out = wrap("local x = 1")
	check("function-less source skipped", out == nil)
end

print(("srcedit: %d passed, %d failed"):format(passed, failed))
for _, f in ipairs(failures) do
	print("FAIL", f)
end
if failed > 0 then
	error(failed .. " failures")
end
