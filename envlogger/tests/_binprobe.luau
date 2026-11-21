local s = "A\0B\0C\0D"
print("len", #s)
local sub = s:sub(2, 6)
print("sublen", #sub)
local bs = {}
for i = 1, #sub do bs[#bs+1] = sub:byte(i) end
print("bytes", table.concat(bs, ","))
local big = string.rep("\1\0\2\0", 512)
print("biglen", #big)
local b2 = big:sub(1000, 1010)
print("b2len", #b2)
print("b2bytes", b2:byte(1), b2:byte(2))
