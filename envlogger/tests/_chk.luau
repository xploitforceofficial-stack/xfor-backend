local fs = require("@lune/fs")
local src = fs.readFile("tests/_wt.luau")

local ok1, err1 = pcall(function()
	local luau = require("@lune/luau")
	luau.load(src, "@test")
end)
print("wt compile ok=" .. tostring(ok1) .. " err=" .. tostring(err1))

local line
for l in (src .. "\n"):gmatch("(.-)\n") do
	if l:find("{ \"DBG16\",", 1, true) then
		local a1, b1 = l:find("{ \"DBG16\", \"", 1, true)
		local a2 = l:find("\", \"after\" }", 1, true)
		if a1 and a2 then
			local patClose = l:find("\", \"", b1 + 1, true)
			local injStart = if patClose then patClose + 4 else b1 + 1
			local inj = l:sub(injStart, a2 - 1)
			local luau2 = require("@lune/luau")
			local okI, fnI, errI = pcall(luau2.load, inj, "@dbg16")
			if not okI then
				fnI, errI = nil, tostring(fnI)
			end
			print("DBG16 injected len=" .. #inj .. " compile=" .. tostring(fnI ~= nil) .. " err=" .. tostring(errI))
		end
	end
end

for l in (src .. "\n"):gmatch("(.-)\n") do
	if l:find('return " do local _D=__SSDIAG2__', 1, true) then
		line = l
		break
	end
end
assert(line, "mkXC line not found")
local expr = line:match("^%s*return%s+(.*)$")
assert(expr, "expr not found")

local builder, berr
do
	local luau = require("@lune/luau")
	local fn, e = luau.load("local tag='A' local k=\"_D['CA']\" return (" .. expr .. ")", "@builder")
	builder, berr = fn, e
end
print("builder ok=" .. tostring(builder ~= nil) .. " err=" .. tostring(berr))
if builder then
	local injected = builder()
	print("injected len=" .. #injected)
	fs.writeFile("tests/_inj.txt", injected)
	local luau = require("@lune/luau")
	local ok, fn, e = pcall(luau.load, injected, "@injected")
	if not ok then
		print("LOAD THREW: " .. tostring(fn))
		fn, e = nil, tostring(fn)
	end
	print("compile=" .. tostring(fn ~= nil) .. " err=" .. tostring(e))
	if not fn then
		print("HEAD: " .. injected:sub(1, 220))
		print("TAIL: " .. injected:sub(-320))
		local _, nEnd = injected:gsub("%f[%a]end%f[%A]", "")
		local _, nDo = injected:gsub("%f[%a]do%f[%A]", "")
		local _, nThen = injected:gsub("%f[%a]then%f[%A]", "")
		local _, nFunction = injected:gsub("%f[%a]function%f[%A]", "")
		local _, nRepeat = injected:gsub("%f[%a]repeat%f[%A]", "")
		local _, nIf = injected:gsub("%f[%a]if%f[%A]", "")
		local _, nFor = injected:gsub("%f[%a]for%f[%A]", "")
		local _, nWhile = injected:gsub("%f[%a]while%f[%A]", "")
		print("end=" .. nEnd .. " do=" .. nDo .. " then=" .. nThen .. " function=" .. nFunction .. " if=" .. nIf .. " repeat=" .. nRepeat .. " for=" .. nFor .. " while=" .. nWhile)
	end
end
