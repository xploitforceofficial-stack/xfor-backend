local Instrument = require("../src/core/instrument")

local samples = {
	"local a = b * (c + 1)",
	"local x = t[i] .. s",
	"return (a % b) + #s",
	"local q = nil * 3",
	"for i=1,10 do acc = acc + i end",
	"local z = 1 + 2",
	"x = y or _GAnil()",
}

for _, s in ipairs(samples) do
	local out, err, n = Instrument.guardArith(s)
	print(string.format("in : %s", s))
	print(string.format("out: %s   (n=%s err=%s)", tostring(out), tostring(n), tostring(err)))
	print("")
end

local hard = {
	"local v; v=g[0b101]-1*0X4",
	"local a=(b)*(c); local d=a..(e)",
	"L[0X7][0X22]=o.x;L=l[0X39](L,l[0X_A])(o,w,o.F,l[0X20],v)",
	"if a then b + c end",
	"while R do return 86~-0XA3 end",
	"local q={}; q.x=(a)*(b); return q",
}
local luau = require("@lune/luau")
for _, s in ipairs(hard) do
	local out, err, n = Instrument.guardArith(s)
	local okC, res = pcall(luau.load, out or s, "@t")
	print(string.format("hard in : %s", s))
	print(string.format("hard out: %s   (n=%s compiles=%s)", tostring(out), tostring(n), tostring(okC)))
	print("")
end

for _, s in ipairs(samples) do
	local out = Instrument.guardArith(s)
	local okC, res = pcall(luau.load, out or s, "@t")
	print(string.format("compiles=%s  <- %s", tostring(okC), tostring(out)))
end
