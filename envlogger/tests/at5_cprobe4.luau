local ok, source, line, name, params, vararg, func = pcall(debug.info, string.byte, "slnaf")
print("pcall ok:", ok)
if ok then
	print("string.byte slnaf:", source, line, name, params, vararg, func)
else
	print("err:", source)
end

local f = function(x) return x end
local s2, l2, n2, p2, v2 = debug.info(f, "slnaf")
print("luau fn slnaf:", s2, l2, n2, p2, v2)
