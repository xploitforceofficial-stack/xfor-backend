local v = string.sub("abc", 1, 1)
print("SUB", type(v), tostring(v), rawequal(v, "a"), #v)
print("BAND", type(bit32.band(7, 3)), bit32.band(7, 3) == 3)
local t = {}
print("TBL", type(t), getmetatable(t) == nil, rawequal(t, t))
print("CHAR", type(string.char(97)), rawequal(string.char(97), "a"))
print("CONCAT", type(v .. "b"), v .. "b")
print("EQ", v == "a", v == string.sub("abc", 1, 1))
local big = string.rep("x", 50000)
local t0 = os.clock()
local acc = 0
for i = 1, 50000 do acc = acc + #string.sub(big, (i % 40000) + 1, (i % 40000) + 1) end
print("LOOP_DONE", acc)
