local a, b, c, d, e = debug.info(getmetatable, "slnaf")
print("real getmetatable:", a, b, c, d, e)
local f = function(x) return x end
local a2, b2, c2, d2, e2 = debug.info(f, "slnaf")
print("lua closure:", a2, b2, c2, d2, e2)
