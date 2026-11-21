local source, line, name, params, vararg, func = debug.info(string.byte, "slnafu")
print("string.byte slnafu:", source, line, name, params, vararg, func)

local f = function(x) return x end
local s2, l2, n2, p2, v2 = debug.info(f, "slnaf")
print("luau fn slnaf:", s2, l2, n2, p2, v2)
